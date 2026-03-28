// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ocr_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

OCRSession _$OCRSessionFromJson(Map<String, dynamic> json) {
  return _OCRSession.fromJson(json);
}

/// @nodoc
mixin _$OCRSession {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'tenant_id')
  String get tenantId => throw _privateConstructorUsedError;
  @JsonKey(name: 'user_id')
  String get userId => throw _privateConstructorUsedError;
  @JsonKey(name: 'shop_id')
  String get shopId => throw _privateConstructorUsedError;
  @JsonKey(name: 'image_url')
  String get imageUrl => throw _privateConstructorUsedError;
  @JsonKey(name: 'image_size')
  int get imageSize => throw _privateConstructorUsedError;
  @JsonKey(name: 'image_type')
  String get imageType => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  @JsonKey(name: 'ocr_provider')
  String get ocrProvider => throw _privateConstructorUsedError;
  @JsonKey(name: 'raw_text')
  String? get rawText => throw _privateConstructorUsedError;
  @JsonKey(name: 'processed_at')
  DateTime? get processedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'error_message')
  String? get errorMessage => throw _privateConstructorUsedError;
  @JsonKey(name: 'confidence_score')
  double? get confidenceScore => throw _privateConstructorUsedError;
  @JsonKey(name: 'processing_time_ms')
  int? get processingTimeMs => throw _privateConstructorUsedError;
  @JsonKey(name: 'receipt_date')
  DateTime? get receiptDate => throw _privateConstructorUsedError;
  @JsonKey(name: 'receipt_number')
  String? get receiptNumber => throw _privateConstructorUsedError;
  @JsonKey(name: 'vendor_name')
  String? get vendorName => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_amount')
  double? get totalAmount => throw _privateConstructorUsedError;
  @JsonKey(name: 'session_type')
  String get sessionType => throw _privateConstructorUsedError;
  @JsonKey(name: 'expires_at')
  DateTime get expiresAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'updated_at')
  DateTime get updatedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'extracted_items')
  List<OCRExtractedItem> get extractedItems =>
      throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $OCRSessionCopyWith<OCRSession> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OCRSessionCopyWith<$Res> {
  factory $OCRSessionCopyWith(
          OCRSession value, $Res Function(OCRSession) then) =
      _$OCRSessionCopyWithImpl<$Res, OCRSession>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'tenant_id') String tenantId,
      @JsonKey(name: 'user_id') String userId,
      @JsonKey(name: 'shop_id') String shopId,
      @JsonKey(name: 'image_url') String imageUrl,
      @JsonKey(name: 'image_size') int imageSize,
      @JsonKey(name: 'image_type') String imageType,
      String status,
      @JsonKey(name: 'ocr_provider') String ocrProvider,
      @JsonKey(name: 'raw_text') String? rawText,
      @JsonKey(name: 'processed_at') DateTime? processedAt,
      @JsonKey(name: 'error_message') String? errorMessage,
      @JsonKey(name: 'confidence_score') double? confidenceScore,
      @JsonKey(name: 'processing_time_ms') int? processingTimeMs,
      @JsonKey(name: 'receipt_date') DateTime? receiptDate,
      @JsonKey(name: 'receipt_number') String? receiptNumber,
      @JsonKey(name: 'vendor_name') String? vendorName,
      @JsonKey(name: 'total_amount') double? totalAmount,
      @JsonKey(name: 'session_type') String sessionType,
      @JsonKey(name: 'expires_at') DateTime expiresAt,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'updated_at') DateTime updatedAt,
      @JsonKey(name: 'extracted_items') List<OCRExtractedItem> extractedItems});
}

/// @nodoc
class _$OCRSessionCopyWithImpl<$Res, $Val extends OCRSession>
    implements $OCRSessionCopyWith<$Res> {
  _$OCRSessionCopyWithImpl(this._value, this._then);

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
    Object? imageUrl = null,
    Object? imageSize = null,
    Object? imageType = null,
    Object? status = null,
    Object? ocrProvider = null,
    Object? rawText = freezed,
    Object? processedAt = freezed,
    Object? errorMessage = freezed,
    Object? confidenceScore = freezed,
    Object? processingTimeMs = freezed,
    Object? receiptDate = freezed,
    Object? receiptNumber = freezed,
    Object? vendorName = freezed,
    Object? totalAmount = freezed,
    Object? sessionType = null,
    Object? expiresAt = null,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? extractedItems = null,
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
      imageUrl: null == imageUrl
          ? _value.imageUrl
          : imageUrl // ignore: cast_nullable_to_non_nullable
              as String,
      imageSize: null == imageSize
          ? _value.imageSize
          : imageSize // ignore: cast_nullable_to_non_nullable
              as int,
      imageType: null == imageType
          ? _value.imageType
          : imageType // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      ocrProvider: null == ocrProvider
          ? _value.ocrProvider
          : ocrProvider // ignore: cast_nullable_to_non_nullable
              as String,
      rawText: freezed == rawText
          ? _value.rawText
          : rawText // ignore: cast_nullable_to_non_nullable
              as String?,
      processedAt: freezed == processedAt
          ? _value.processedAt
          : processedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      confidenceScore: freezed == confidenceScore
          ? _value.confidenceScore
          : confidenceScore // ignore: cast_nullable_to_non_nullable
              as double?,
      processingTimeMs: freezed == processingTimeMs
          ? _value.processingTimeMs
          : processingTimeMs // ignore: cast_nullable_to_non_nullable
              as int?,
      receiptDate: freezed == receiptDate
          ? _value.receiptDate
          : receiptDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      receiptNumber: freezed == receiptNumber
          ? _value.receiptNumber
          : receiptNumber // ignore: cast_nullable_to_non_nullable
              as String?,
      vendorName: freezed == vendorName
          ? _value.vendorName
          : vendorName // ignore: cast_nullable_to_non_nullable
              as String?,
      totalAmount: freezed == totalAmount
          ? _value.totalAmount
          : totalAmount // ignore: cast_nullable_to_non_nullable
              as double?,
      sessionType: null == sessionType
          ? _value.sessionType
          : sessionType // ignore: cast_nullable_to_non_nullable
              as String,
      expiresAt: null == expiresAt
          ? _value.expiresAt
          : expiresAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      extractedItems: null == extractedItems
          ? _value.extractedItems
          : extractedItems // ignore: cast_nullable_to_non_nullable
              as List<OCRExtractedItem>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OCRSessionImplCopyWith<$Res>
    implements $OCRSessionCopyWith<$Res> {
  factory _$$OCRSessionImplCopyWith(
          _$OCRSessionImpl value, $Res Function(_$OCRSessionImpl) then) =
      __$$OCRSessionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'tenant_id') String tenantId,
      @JsonKey(name: 'user_id') String userId,
      @JsonKey(name: 'shop_id') String shopId,
      @JsonKey(name: 'image_url') String imageUrl,
      @JsonKey(name: 'image_size') int imageSize,
      @JsonKey(name: 'image_type') String imageType,
      String status,
      @JsonKey(name: 'ocr_provider') String ocrProvider,
      @JsonKey(name: 'raw_text') String? rawText,
      @JsonKey(name: 'processed_at') DateTime? processedAt,
      @JsonKey(name: 'error_message') String? errorMessage,
      @JsonKey(name: 'confidence_score') double? confidenceScore,
      @JsonKey(name: 'processing_time_ms') int? processingTimeMs,
      @JsonKey(name: 'receipt_date') DateTime? receiptDate,
      @JsonKey(name: 'receipt_number') String? receiptNumber,
      @JsonKey(name: 'vendor_name') String? vendorName,
      @JsonKey(name: 'total_amount') double? totalAmount,
      @JsonKey(name: 'session_type') String sessionType,
      @JsonKey(name: 'expires_at') DateTime expiresAt,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'updated_at') DateTime updatedAt,
      @JsonKey(name: 'extracted_items') List<OCRExtractedItem> extractedItems});
}

/// @nodoc
class __$$OCRSessionImplCopyWithImpl<$Res>
    extends _$OCRSessionCopyWithImpl<$Res, _$OCRSessionImpl>
    implements _$$OCRSessionImplCopyWith<$Res> {
  __$$OCRSessionImplCopyWithImpl(
      _$OCRSessionImpl _value, $Res Function(_$OCRSessionImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? tenantId = null,
    Object? userId = null,
    Object? shopId = null,
    Object? imageUrl = null,
    Object? imageSize = null,
    Object? imageType = null,
    Object? status = null,
    Object? ocrProvider = null,
    Object? rawText = freezed,
    Object? processedAt = freezed,
    Object? errorMessage = freezed,
    Object? confidenceScore = freezed,
    Object? processingTimeMs = freezed,
    Object? receiptDate = freezed,
    Object? receiptNumber = freezed,
    Object? vendorName = freezed,
    Object? totalAmount = freezed,
    Object? sessionType = null,
    Object? expiresAt = null,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? extractedItems = null,
  }) {
    return _then(_$OCRSessionImpl(
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
      imageUrl: null == imageUrl
          ? _value.imageUrl
          : imageUrl // ignore: cast_nullable_to_non_nullable
              as String,
      imageSize: null == imageSize
          ? _value.imageSize
          : imageSize // ignore: cast_nullable_to_non_nullable
              as int,
      imageType: null == imageType
          ? _value.imageType
          : imageType // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      ocrProvider: null == ocrProvider
          ? _value.ocrProvider
          : ocrProvider // ignore: cast_nullable_to_non_nullable
              as String,
      rawText: freezed == rawText
          ? _value.rawText
          : rawText // ignore: cast_nullable_to_non_nullable
              as String?,
      processedAt: freezed == processedAt
          ? _value.processedAt
          : processedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      confidenceScore: freezed == confidenceScore
          ? _value.confidenceScore
          : confidenceScore // ignore: cast_nullable_to_non_nullable
              as double?,
      processingTimeMs: freezed == processingTimeMs
          ? _value.processingTimeMs
          : processingTimeMs // ignore: cast_nullable_to_non_nullable
              as int?,
      receiptDate: freezed == receiptDate
          ? _value.receiptDate
          : receiptDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      receiptNumber: freezed == receiptNumber
          ? _value.receiptNumber
          : receiptNumber // ignore: cast_nullable_to_non_nullable
              as String?,
      vendorName: freezed == vendorName
          ? _value.vendorName
          : vendorName // ignore: cast_nullable_to_non_nullable
              as String?,
      totalAmount: freezed == totalAmount
          ? _value.totalAmount
          : totalAmount // ignore: cast_nullable_to_non_nullable
              as double?,
      sessionType: null == sessionType
          ? _value.sessionType
          : sessionType // ignore: cast_nullable_to_non_nullable
              as String,
      expiresAt: null == expiresAt
          ? _value.expiresAt
          : expiresAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      extractedItems: null == extractedItems
          ? _value._extractedItems
          : extractedItems // ignore: cast_nullable_to_non_nullable
              as List<OCRExtractedItem>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OCRSessionImpl implements _OCRSession {
  const _$OCRSessionImpl(
      {required this.id,
      @JsonKey(name: 'tenant_id') required this.tenantId,
      @JsonKey(name: 'user_id') required this.userId,
      @JsonKey(name: 'shop_id') required this.shopId,
      @JsonKey(name: 'image_url') required this.imageUrl,
      @JsonKey(name: 'image_size') required this.imageSize,
      @JsonKey(name: 'image_type') required this.imageType,
      required this.status,
      @JsonKey(name: 'ocr_provider') this.ocrProvider = 'google_vision',
      @JsonKey(name: 'raw_text') this.rawText,
      @JsonKey(name: 'processed_at') this.processedAt,
      @JsonKey(name: 'error_message') this.errorMessage,
      @JsonKey(name: 'confidence_score') this.confidenceScore,
      @JsonKey(name: 'processing_time_ms') this.processingTimeMs,
      @JsonKey(name: 'receipt_date') this.receiptDate,
      @JsonKey(name: 'receipt_number') this.receiptNumber,
      @JsonKey(name: 'vendor_name') this.vendorName,
      @JsonKey(name: 'total_amount') this.totalAmount,
      @JsonKey(name: 'session_type') this.sessionType = 'quick_sale',
      @JsonKey(name: 'expires_at') required this.expiresAt,
      @JsonKey(name: 'created_at') required this.createdAt,
      @JsonKey(name: 'updated_at') required this.updatedAt,
      @JsonKey(name: 'extracted_items')
      final List<OCRExtractedItem> extractedItems = const []})
      : _extractedItems = extractedItems;

  factory _$OCRSessionImpl.fromJson(Map<String, dynamic> json) =>
      _$$OCRSessionImplFromJson(json);

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
  @JsonKey(name: 'image_url')
  final String imageUrl;
  @override
  @JsonKey(name: 'image_size')
  final int imageSize;
  @override
  @JsonKey(name: 'image_type')
  final String imageType;
  @override
  final String status;
  @override
  @JsonKey(name: 'ocr_provider')
  final String ocrProvider;
  @override
  @JsonKey(name: 'raw_text')
  final String? rawText;
  @override
  @JsonKey(name: 'processed_at')
  final DateTime? processedAt;
  @override
  @JsonKey(name: 'error_message')
  final String? errorMessage;
  @override
  @JsonKey(name: 'confidence_score')
  final double? confidenceScore;
  @override
  @JsonKey(name: 'processing_time_ms')
  final int? processingTimeMs;
  @override
  @JsonKey(name: 'receipt_date')
  final DateTime? receiptDate;
  @override
  @JsonKey(name: 'receipt_number')
  final String? receiptNumber;
  @override
  @JsonKey(name: 'vendor_name')
  final String? vendorName;
  @override
  @JsonKey(name: 'total_amount')
  final double? totalAmount;
  @override
  @JsonKey(name: 'session_type')
  final String sessionType;
  @override
  @JsonKey(name: 'expires_at')
  final DateTime expiresAt;
  @override
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @override
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;
  final List<OCRExtractedItem> _extractedItems;
  @override
  @JsonKey(name: 'extracted_items')
  List<OCRExtractedItem> get extractedItems {
    if (_extractedItems is EqualUnmodifiableListView) return _extractedItems;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_extractedItems);
  }

  @override
  String toString() {
    return 'OCRSession(id: $id, tenantId: $tenantId, userId: $userId, shopId: $shopId, imageUrl: $imageUrl, imageSize: $imageSize, imageType: $imageType, status: $status, ocrProvider: $ocrProvider, rawText: $rawText, processedAt: $processedAt, errorMessage: $errorMessage, confidenceScore: $confidenceScore, processingTimeMs: $processingTimeMs, receiptDate: $receiptDate, receiptNumber: $receiptNumber, vendorName: $vendorName, totalAmount: $totalAmount, sessionType: $sessionType, expiresAt: $expiresAt, createdAt: $createdAt, updatedAt: $updatedAt, extractedItems: $extractedItems)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OCRSessionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.tenantId, tenantId) ||
                other.tenantId == tenantId) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.shopId, shopId) || other.shopId == shopId) &&
            (identical(other.imageUrl, imageUrl) ||
                other.imageUrl == imageUrl) &&
            (identical(other.imageSize, imageSize) ||
                other.imageSize == imageSize) &&
            (identical(other.imageType, imageType) ||
                other.imageType == imageType) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.ocrProvider, ocrProvider) ||
                other.ocrProvider == ocrProvider) &&
            (identical(other.rawText, rawText) || other.rawText == rawText) &&
            (identical(other.processedAt, processedAt) ||
                other.processedAt == processedAt) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            (identical(other.confidenceScore, confidenceScore) ||
                other.confidenceScore == confidenceScore) &&
            (identical(other.processingTimeMs, processingTimeMs) ||
                other.processingTimeMs == processingTimeMs) &&
            (identical(other.receiptDate, receiptDate) ||
                other.receiptDate == receiptDate) &&
            (identical(other.receiptNumber, receiptNumber) ||
                other.receiptNumber == receiptNumber) &&
            (identical(other.vendorName, vendorName) ||
                other.vendorName == vendorName) &&
            (identical(other.totalAmount, totalAmount) ||
                other.totalAmount == totalAmount) &&
            (identical(other.sessionType, sessionType) ||
                other.sessionType == sessionType) &&
            (identical(other.expiresAt, expiresAt) ||
                other.expiresAt == expiresAt) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            const DeepCollectionEquality()
                .equals(other._extractedItems, _extractedItems));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        tenantId,
        userId,
        shopId,
        imageUrl,
        imageSize,
        imageType,
        status,
        ocrProvider,
        rawText,
        processedAt,
        errorMessage,
        confidenceScore,
        processingTimeMs,
        receiptDate,
        receiptNumber,
        vendorName,
        totalAmount,
        sessionType,
        expiresAt,
        createdAt,
        updatedAt,
        const DeepCollectionEquality().hash(_extractedItems)
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$OCRSessionImplCopyWith<_$OCRSessionImpl> get copyWith =>
      __$$OCRSessionImplCopyWithImpl<_$OCRSessionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OCRSessionImplToJson(
      this,
    );
  }
}

abstract class _OCRSession implements OCRSession {
  const factory _OCRSession(
      {required final String id,
      @JsonKey(name: 'tenant_id') required final String tenantId,
      @JsonKey(name: 'user_id') required final String userId,
      @JsonKey(name: 'shop_id') required final String shopId,
      @JsonKey(name: 'image_url') required final String imageUrl,
      @JsonKey(name: 'image_size') required final int imageSize,
      @JsonKey(name: 'image_type') required final String imageType,
      required final String status,
      @JsonKey(name: 'ocr_provider') final String ocrProvider,
      @JsonKey(name: 'raw_text') final String? rawText,
      @JsonKey(name: 'processed_at') final DateTime? processedAt,
      @JsonKey(name: 'error_message') final String? errorMessage,
      @JsonKey(name: 'confidence_score') final double? confidenceScore,
      @JsonKey(name: 'processing_time_ms') final int? processingTimeMs,
      @JsonKey(name: 'receipt_date') final DateTime? receiptDate,
      @JsonKey(name: 'receipt_number') final String? receiptNumber,
      @JsonKey(name: 'vendor_name') final String? vendorName,
      @JsonKey(name: 'total_amount') final double? totalAmount,
      @JsonKey(name: 'session_type') final String sessionType,
      @JsonKey(name: 'expires_at') required final DateTime expiresAt,
      @JsonKey(name: 'created_at') required final DateTime createdAt,
      @JsonKey(name: 'updated_at') required final DateTime updatedAt,
      @JsonKey(name: 'extracted_items')
      final List<OCRExtractedItem> extractedItems}) = _$OCRSessionImpl;

  factory _OCRSession.fromJson(Map<String, dynamic> json) =
      _$OCRSessionImpl.fromJson;

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
  @JsonKey(name: 'image_url')
  String get imageUrl;
  @override
  @JsonKey(name: 'image_size')
  int get imageSize;
  @override
  @JsonKey(name: 'image_type')
  String get imageType;
  @override
  String get status;
  @override
  @JsonKey(name: 'ocr_provider')
  String get ocrProvider;
  @override
  @JsonKey(name: 'raw_text')
  String? get rawText;
  @override
  @JsonKey(name: 'processed_at')
  DateTime? get processedAt;
  @override
  @JsonKey(name: 'error_message')
  String? get errorMessage;
  @override
  @JsonKey(name: 'confidence_score')
  double? get confidenceScore;
  @override
  @JsonKey(name: 'processing_time_ms')
  int? get processingTimeMs;
  @override
  @JsonKey(name: 'receipt_date')
  DateTime? get receiptDate;
  @override
  @JsonKey(name: 'receipt_number')
  String? get receiptNumber;
  @override
  @JsonKey(name: 'vendor_name')
  String? get vendorName;
  @override
  @JsonKey(name: 'total_amount')
  double? get totalAmount;
  @override
  @JsonKey(name: 'session_type')
  String get sessionType;
  @override
  @JsonKey(name: 'expires_at')
  DateTime get expiresAt;
  @override
  @JsonKey(name: 'created_at')
  DateTime get createdAt;
  @override
  @JsonKey(name: 'updated_at')
  DateTime get updatedAt;
  @override
  @JsonKey(name: 'extracted_items')
  List<OCRExtractedItem> get extractedItems;
  @override
  @JsonKey(ignore: true)
  _$$OCRSessionImplCopyWith<_$OCRSessionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

OCRExtractedItem _$OCRExtractedItemFromJson(Map<String, dynamic> json) {
  return _OCRExtractedItem.fromJson(json);
}

/// @nodoc
mixin _$OCRExtractedItem {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'session_id')
  String get sessionId => throw _privateConstructorUsedError;
  @JsonKey(name: 'extracted_text')
  String get extractedText => throw _privateConstructorUsedError;
  @JsonKey(name: 'brand_text')
  String? get brandText => throw _privateConstructorUsedError;
  @JsonKey(name: 'size_text')
  String? get sizeText => throw _privateConstructorUsedError;
  @JsonKey(name: 'quantity_text')
  String? get quantityText => throw _privateConstructorUsedError;
  @JsonKey(name: 'price_text')
  String? get priceText => throw _privateConstructorUsedError;
  @JsonKey(name: 'parsed_quantity')
  int? get parsedQuantity => throw _privateConstructorUsedError;
  @JsonKey(name: 'parsed_price')
  double? get parsedPrice => throw _privateConstructorUsedError;
  @JsonKey(name: 'parsed_size')
  String? get parsedSize =>
      throw _privateConstructorUsedError; // Stock tracking fields
  @JsonKey(name: 'rate_per_unit')
  double? get ratePerUnit => throw _privateConstructorUsedError;
  @JsonKey(name: 'opening_stock')
  int? get openingStock => throw _privateConstructorUsedError;
  @JsonKey(name: 'closing_stock')
  int? get closingStock => throw _privateConstructorUsedError;
  @JsonKey(name: 'row_number')
  int? get rowNumber => throw _privateConstructorUsedError;
  @JsonKey(name: 'matched_product_id')
  String? get matchedProductId => throw _privateConstructorUsedError;
  @JsonKey(name: 'matched_brand_id')
  String? get matchedBrandId => throw _privateConstructorUsedError;
  @JsonKey(name: 'matched_variant_id')
  String? get matchedVariantId => throw _privateConstructorUsedError;
  @JsonKey(name: 'match_confidence')
  double get matchConfidence => throw _privateConstructorUsedError;
  @JsonKey(name: 'match_method')
  String? get matchMethod => throw _privateConstructorUsedError;
  @JsonKey(name: 'match_details')
  Map<String, dynamic>? get matchDetails => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_confirmed')
  bool get isConfirmed => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_rejected')
  bool get isRejected => throw _privateConstructorUsedError;
  @JsonKey(name: 'user_corrected_product_id')
  String? get userCorrectedProductId => throw _privateConstructorUsedError;
  @JsonKey(name: 'user_corrected_quantity')
  int? get userCorrectedQuantity => throw _privateConstructorUsedError;
  @JsonKey(name: 'correction_reason')
  String? get correctionReason => throw _privateConstructorUsedError;
  @JsonKey(name: 'line_number')
  int? get lineNumber => throw _privateConstructorUsedError;
  @JsonKey(name: 'bounding_box')
  Map<String, dynamic>? get boundingBox => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'updated_at')
  DateTime get updatedAt =>
      throw _privateConstructorUsedError; // Related data (not serialized - runtime only)
  @JsonKey(ignore: true)
  Product? get matchedProduct => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  Brand? get matchedBrand => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  BrandVariant? get matchedVariant => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $OCRExtractedItemCopyWith<OCRExtractedItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OCRExtractedItemCopyWith<$Res> {
  factory $OCRExtractedItemCopyWith(
          OCRExtractedItem value, $Res Function(OCRExtractedItem) then) =
      _$OCRExtractedItemCopyWithImpl<$Res, OCRExtractedItem>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'session_id') String sessionId,
      @JsonKey(name: 'extracted_text') String extractedText,
      @JsonKey(name: 'brand_text') String? brandText,
      @JsonKey(name: 'size_text') String? sizeText,
      @JsonKey(name: 'quantity_text') String? quantityText,
      @JsonKey(name: 'price_text') String? priceText,
      @JsonKey(name: 'parsed_quantity') int? parsedQuantity,
      @JsonKey(name: 'parsed_price') double? parsedPrice,
      @JsonKey(name: 'parsed_size') String? parsedSize,
      @JsonKey(name: 'rate_per_unit') double? ratePerUnit,
      @JsonKey(name: 'opening_stock') int? openingStock,
      @JsonKey(name: 'closing_stock') int? closingStock,
      @JsonKey(name: 'row_number') int? rowNumber,
      @JsonKey(name: 'matched_product_id') String? matchedProductId,
      @JsonKey(name: 'matched_brand_id') String? matchedBrandId,
      @JsonKey(name: 'matched_variant_id') String? matchedVariantId,
      @JsonKey(name: 'match_confidence') double matchConfidence,
      @JsonKey(name: 'match_method') String? matchMethod,
      @JsonKey(name: 'match_details') Map<String, dynamic>? matchDetails,
      @JsonKey(name: 'is_confirmed') bool isConfirmed,
      @JsonKey(name: 'is_rejected') bool isRejected,
      @JsonKey(name: 'user_corrected_product_id')
      String? userCorrectedProductId,
      @JsonKey(name: 'user_corrected_quantity') int? userCorrectedQuantity,
      @JsonKey(name: 'correction_reason') String? correctionReason,
      @JsonKey(name: 'line_number') int? lineNumber,
      @JsonKey(name: 'bounding_box') Map<String, dynamic>? boundingBox,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'updated_at') DateTime updatedAt,
      @JsonKey(ignore: true) Product? matchedProduct,
      @JsonKey(ignore: true) Brand? matchedBrand,
      @JsonKey(ignore: true) BrandVariant? matchedVariant});
}

/// @nodoc
class _$OCRExtractedItemCopyWithImpl<$Res, $Val extends OCRExtractedItem>
    implements $OCRExtractedItemCopyWith<$Res> {
  _$OCRExtractedItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? sessionId = null,
    Object? extractedText = null,
    Object? brandText = freezed,
    Object? sizeText = freezed,
    Object? quantityText = freezed,
    Object? priceText = freezed,
    Object? parsedQuantity = freezed,
    Object? parsedPrice = freezed,
    Object? parsedSize = freezed,
    Object? ratePerUnit = freezed,
    Object? openingStock = freezed,
    Object? closingStock = freezed,
    Object? rowNumber = freezed,
    Object? matchedProductId = freezed,
    Object? matchedBrandId = freezed,
    Object? matchedVariantId = freezed,
    Object? matchConfidence = null,
    Object? matchMethod = freezed,
    Object? matchDetails = freezed,
    Object? isConfirmed = null,
    Object? isRejected = null,
    Object? userCorrectedProductId = freezed,
    Object? userCorrectedQuantity = freezed,
    Object? correctionReason = freezed,
    Object? lineNumber = freezed,
    Object? boundingBox = freezed,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? matchedProduct = freezed,
    Object? matchedBrand = freezed,
    Object? matchedVariant = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      sessionId: null == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String,
      extractedText: null == extractedText
          ? _value.extractedText
          : extractedText // ignore: cast_nullable_to_non_nullable
              as String,
      brandText: freezed == brandText
          ? _value.brandText
          : brandText // ignore: cast_nullable_to_non_nullable
              as String?,
      sizeText: freezed == sizeText
          ? _value.sizeText
          : sizeText // ignore: cast_nullable_to_non_nullable
              as String?,
      quantityText: freezed == quantityText
          ? _value.quantityText
          : quantityText // ignore: cast_nullable_to_non_nullable
              as String?,
      priceText: freezed == priceText
          ? _value.priceText
          : priceText // ignore: cast_nullable_to_non_nullable
              as String?,
      parsedQuantity: freezed == parsedQuantity
          ? _value.parsedQuantity
          : parsedQuantity // ignore: cast_nullable_to_non_nullable
              as int?,
      parsedPrice: freezed == parsedPrice
          ? _value.parsedPrice
          : parsedPrice // ignore: cast_nullable_to_non_nullable
              as double?,
      parsedSize: freezed == parsedSize
          ? _value.parsedSize
          : parsedSize // ignore: cast_nullable_to_non_nullable
              as String?,
      ratePerUnit: freezed == ratePerUnit
          ? _value.ratePerUnit
          : ratePerUnit // ignore: cast_nullable_to_non_nullable
              as double?,
      openingStock: freezed == openingStock
          ? _value.openingStock
          : openingStock // ignore: cast_nullable_to_non_nullable
              as int?,
      closingStock: freezed == closingStock
          ? _value.closingStock
          : closingStock // ignore: cast_nullable_to_non_nullable
              as int?,
      rowNumber: freezed == rowNumber
          ? _value.rowNumber
          : rowNumber // ignore: cast_nullable_to_non_nullable
              as int?,
      matchedProductId: freezed == matchedProductId
          ? _value.matchedProductId
          : matchedProductId // ignore: cast_nullable_to_non_nullable
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
      matchMethod: freezed == matchMethod
          ? _value.matchMethod
          : matchMethod // ignore: cast_nullable_to_non_nullable
              as String?,
      matchDetails: freezed == matchDetails
          ? _value.matchDetails
          : matchDetails // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      isConfirmed: null == isConfirmed
          ? _value.isConfirmed
          : isConfirmed // ignore: cast_nullable_to_non_nullable
              as bool,
      isRejected: null == isRejected
          ? _value.isRejected
          : isRejected // ignore: cast_nullable_to_non_nullable
              as bool,
      userCorrectedProductId: freezed == userCorrectedProductId
          ? _value.userCorrectedProductId
          : userCorrectedProductId // ignore: cast_nullable_to_non_nullable
              as String?,
      userCorrectedQuantity: freezed == userCorrectedQuantity
          ? _value.userCorrectedQuantity
          : userCorrectedQuantity // ignore: cast_nullable_to_non_nullable
              as int?,
      correctionReason: freezed == correctionReason
          ? _value.correctionReason
          : correctionReason // ignore: cast_nullable_to_non_nullable
              as String?,
      lineNumber: freezed == lineNumber
          ? _value.lineNumber
          : lineNumber // ignore: cast_nullable_to_non_nullable
              as int?,
      boundingBox: freezed == boundingBox
          ? _value.boundingBox
          : boundingBox // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      matchedProduct: freezed == matchedProduct
          ? _value.matchedProduct
          : matchedProduct // ignore: cast_nullable_to_non_nullable
              as Product?,
      matchedBrand: freezed == matchedBrand
          ? _value.matchedBrand
          : matchedBrand // ignore: cast_nullable_to_non_nullable
              as Brand?,
      matchedVariant: freezed == matchedVariant
          ? _value.matchedVariant
          : matchedVariant // ignore: cast_nullable_to_non_nullable
              as BrandVariant?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OCRExtractedItemImplCopyWith<$Res>
    implements $OCRExtractedItemCopyWith<$Res> {
  factory _$$OCRExtractedItemImplCopyWith(_$OCRExtractedItemImpl value,
          $Res Function(_$OCRExtractedItemImpl) then) =
      __$$OCRExtractedItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'session_id') String sessionId,
      @JsonKey(name: 'extracted_text') String extractedText,
      @JsonKey(name: 'brand_text') String? brandText,
      @JsonKey(name: 'size_text') String? sizeText,
      @JsonKey(name: 'quantity_text') String? quantityText,
      @JsonKey(name: 'price_text') String? priceText,
      @JsonKey(name: 'parsed_quantity') int? parsedQuantity,
      @JsonKey(name: 'parsed_price') double? parsedPrice,
      @JsonKey(name: 'parsed_size') String? parsedSize,
      @JsonKey(name: 'rate_per_unit') double? ratePerUnit,
      @JsonKey(name: 'opening_stock') int? openingStock,
      @JsonKey(name: 'closing_stock') int? closingStock,
      @JsonKey(name: 'row_number') int? rowNumber,
      @JsonKey(name: 'matched_product_id') String? matchedProductId,
      @JsonKey(name: 'matched_brand_id') String? matchedBrandId,
      @JsonKey(name: 'matched_variant_id') String? matchedVariantId,
      @JsonKey(name: 'match_confidence') double matchConfidence,
      @JsonKey(name: 'match_method') String? matchMethod,
      @JsonKey(name: 'match_details') Map<String, dynamic>? matchDetails,
      @JsonKey(name: 'is_confirmed') bool isConfirmed,
      @JsonKey(name: 'is_rejected') bool isRejected,
      @JsonKey(name: 'user_corrected_product_id')
      String? userCorrectedProductId,
      @JsonKey(name: 'user_corrected_quantity') int? userCorrectedQuantity,
      @JsonKey(name: 'correction_reason') String? correctionReason,
      @JsonKey(name: 'line_number') int? lineNumber,
      @JsonKey(name: 'bounding_box') Map<String, dynamic>? boundingBox,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'updated_at') DateTime updatedAt,
      @JsonKey(ignore: true) Product? matchedProduct,
      @JsonKey(ignore: true) Brand? matchedBrand,
      @JsonKey(ignore: true) BrandVariant? matchedVariant});
}

/// @nodoc
class __$$OCRExtractedItemImplCopyWithImpl<$Res>
    extends _$OCRExtractedItemCopyWithImpl<$Res, _$OCRExtractedItemImpl>
    implements _$$OCRExtractedItemImplCopyWith<$Res> {
  __$$OCRExtractedItemImplCopyWithImpl(_$OCRExtractedItemImpl _value,
      $Res Function(_$OCRExtractedItemImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? sessionId = null,
    Object? extractedText = null,
    Object? brandText = freezed,
    Object? sizeText = freezed,
    Object? quantityText = freezed,
    Object? priceText = freezed,
    Object? parsedQuantity = freezed,
    Object? parsedPrice = freezed,
    Object? parsedSize = freezed,
    Object? ratePerUnit = freezed,
    Object? openingStock = freezed,
    Object? closingStock = freezed,
    Object? rowNumber = freezed,
    Object? matchedProductId = freezed,
    Object? matchedBrandId = freezed,
    Object? matchedVariantId = freezed,
    Object? matchConfidence = null,
    Object? matchMethod = freezed,
    Object? matchDetails = freezed,
    Object? isConfirmed = null,
    Object? isRejected = null,
    Object? userCorrectedProductId = freezed,
    Object? userCorrectedQuantity = freezed,
    Object? correctionReason = freezed,
    Object? lineNumber = freezed,
    Object? boundingBox = freezed,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? matchedProduct = freezed,
    Object? matchedBrand = freezed,
    Object? matchedVariant = freezed,
  }) {
    return _then(_$OCRExtractedItemImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      sessionId: null == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String,
      extractedText: null == extractedText
          ? _value.extractedText
          : extractedText // ignore: cast_nullable_to_non_nullable
              as String,
      brandText: freezed == brandText
          ? _value.brandText
          : brandText // ignore: cast_nullable_to_non_nullable
              as String?,
      sizeText: freezed == sizeText
          ? _value.sizeText
          : sizeText // ignore: cast_nullable_to_non_nullable
              as String?,
      quantityText: freezed == quantityText
          ? _value.quantityText
          : quantityText // ignore: cast_nullable_to_non_nullable
              as String?,
      priceText: freezed == priceText
          ? _value.priceText
          : priceText // ignore: cast_nullable_to_non_nullable
              as String?,
      parsedQuantity: freezed == parsedQuantity
          ? _value.parsedQuantity
          : parsedQuantity // ignore: cast_nullable_to_non_nullable
              as int?,
      parsedPrice: freezed == parsedPrice
          ? _value.parsedPrice
          : parsedPrice // ignore: cast_nullable_to_non_nullable
              as double?,
      parsedSize: freezed == parsedSize
          ? _value.parsedSize
          : parsedSize // ignore: cast_nullable_to_non_nullable
              as String?,
      ratePerUnit: freezed == ratePerUnit
          ? _value.ratePerUnit
          : ratePerUnit // ignore: cast_nullable_to_non_nullable
              as double?,
      openingStock: freezed == openingStock
          ? _value.openingStock
          : openingStock // ignore: cast_nullable_to_non_nullable
              as int?,
      closingStock: freezed == closingStock
          ? _value.closingStock
          : closingStock // ignore: cast_nullable_to_non_nullable
              as int?,
      rowNumber: freezed == rowNumber
          ? _value.rowNumber
          : rowNumber // ignore: cast_nullable_to_non_nullable
              as int?,
      matchedProductId: freezed == matchedProductId
          ? _value.matchedProductId
          : matchedProductId // ignore: cast_nullable_to_non_nullable
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
      matchMethod: freezed == matchMethod
          ? _value.matchMethod
          : matchMethod // ignore: cast_nullable_to_non_nullable
              as String?,
      matchDetails: freezed == matchDetails
          ? _value._matchDetails
          : matchDetails // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      isConfirmed: null == isConfirmed
          ? _value.isConfirmed
          : isConfirmed // ignore: cast_nullable_to_non_nullable
              as bool,
      isRejected: null == isRejected
          ? _value.isRejected
          : isRejected // ignore: cast_nullable_to_non_nullable
              as bool,
      userCorrectedProductId: freezed == userCorrectedProductId
          ? _value.userCorrectedProductId
          : userCorrectedProductId // ignore: cast_nullable_to_non_nullable
              as String?,
      userCorrectedQuantity: freezed == userCorrectedQuantity
          ? _value.userCorrectedQuantity
          : userCorrectedQuantity // ignore: cast_nullable_to_non_nullable
              as int?,
      correctionReason: freezed == correctionReason
          ? _value.correctionReason
          : correctionReason // ignore: cast_nullable_to_non_nullable
              as String?,
      lineNumber: freezed == lineNumber
          ? _value.lineNumber
          : lineNumber // ignore: cast_nullable_to_non_nullable
              as int?,
      boundingBox: freezed == boundingBox
          ? _value._boundingBox
          : boundingBox // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      matchedProduct: freezed == matchedProduct
          ? _value.matchedProduct
          : matchedProduct // ignore: cast_nullable_to_non_nullable
              as Product?,
      matchedBrand: freezed == matchedBrand
          ? _value.matchedBrand
          : matchedBrand // ignore: cast_nullable_to_non_nullable
              as Brand?,
      matchedVariant: freezed == matchedVariant
          ? _value.matchedVariant
          : matchedVariant // ignore: cast_nullable_to_non_nullable
              as BrandVariant?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OCRExtractedItemImpl implements _OCRExtractedItem {
  const _$OCRExtractedItemImpl(
      {required this.id,
      @JsonKey(name: 'session_id') required this.sessionId,
      @JsonKey(name: 'extracted_text') required this.extractedText,
      @JsonKey(name: 'brand_text') this.brandText,
      @JsonKey(name: 'size_text') this.sizeText,
      @JsonKey(name: 'quantity_text') this.quantityText,
      @JsonKey(name: 'price_text') this.priceText,
      @JsonKey(name: 'parsed_quantity') this.parsedQuantity,
      @JsonKey(name: 'parsed_price') this.parsedPrice,
      @JsonKey(name: 'parsed_size') this.parsedSize,
      @JsonKey(name: 'rate_per_unit') this.ratePerUnit,
      @JsonKey(name: 'opening_stock') this.openingStock,
      @JsonKey(name: 'closing_stock') this.closingStock,
      @JsonKey(name: 'row_number') this.rowNumber,
      @JsonKey(name: 'matched_product_id') this.matchedProductId,
      @JsonKey(name: 'matched_brand_id') this.matchedBrandId,
      @JsonKey(name: 'matched_variant_id') this.matchedVariantId,
      @JsonKey(name: 'match_confidence') required this.matchConfidence,
      @JsonKey(name: 'match_method') this.matchMethod,
      @JsonKey(name: 'match_details') final Map<String, dynamic>? matchDetails,
      @JsonKey(name: 'is_confirmed') this.isConfirmed = false,
      @JsonKey(name: 'is_rejected') this.isRejected = false,
      @JsonKey(name: 'user_corrected_product_id') this.userCorrectedProductId,
      @JsonKey(name: 'user_corrected_quantity') this.userCorrectedQuantity,
      @JsonKey(name: 'correction_reason') this.correctionReason,
      @JsonKey(name: 'line_number') this.lineNumber,
      @JsonKey(name: 'bounding_box') final Map<String, dynamic>? boundingBox,
      @JsonKey(name: 'created_at') required this.createdAt,
      @JsonKey(name: 'updated_at') required this.updatedAt,
      @JsonKey(ignore: true) this.matchedProduct,
      @JsonKey(ignore: true) this.matchedBrand,
      @JsonKey(ignore: true) this.matchedVariant})
      : _matchDetails = matchDetails,
        _boundingBox = boundingBox;

  factory _$OCRExtractedItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$OCRExtractedItemImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'session_id')
  final String sessionId;
  @override
  @JsonKey(name: 'extracted_text')
  final String extractedText;
  @override
  @JsonKey(name: 'brand_text')
  final String? brandText;
  @override
  @JsonKey(name: 'size_text')
  final String? sizeText;
  @override
  @JsonKey(name: 'quantity_text')
  final String? quantityText;
  @override
  @JsonKey(name: 'price_text')
  final String? priceText;
  @override
  @JsonKey(name: 'parsed_quantity')
  final int? parsedQuantity;
  @override
  @JsonKey(name: 'parsed_price')
  final double? parsedPrice;
  @override
  @JsonKey(name: 'parsed_size')
  final String? parsedSize;
// Stock tracking fields
  @override
  @JsonKey(name: 'rate_per_unit')
  final double? ratePerUnit;
  @override
  @JsonKey(name: 'opening_stock')
  final int? openingStock;
  @override
  @JsonKey(name: 'closing_stock')
  final int? closingStock;
  @override
  @JsonKey(name: 'row_number')
  final int? rowNumber;
  @override
  @JsonKey(name: 'matched_product_id')
  final String? matchedProductId;
  @override
  @JsonKey(name: 'matched_brand_id')
  final String? matchedBrandId;
  @override
  @JsonKey(name: 'matched_variant_id')
  final String? matchedVariantId;
  @override
  @JsonKey(name: 'match_confidence')
  final double matchConfidence;
  @override
  @JsonKey(name: 'match_method')
  final String? matchMethod;
  final Map<String, dynamic>? _matchDetails;
  @override
  @JsonKey(name: 'match_details')
  Map<String, dynamic>? get matchDetails {
    final value = _matchDetails;
    if (value == null) return null;
    if (_matchDetails is EqualUnmodifiableMapView) return _matchDetails;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  @JsonKey(name: 'is_confirmed')
  final bool isConfirmed;
  @override
  @JsonKey(name: 'is_rejected')
  final bool isRejected;
  @override
  @JsonKey(name: 'user_corrected_product_id')
  final String? userCorrectedProductId;
  @override
  @JsonKey(name: 'user_corrected_quantity')
  final int? userCorrectedQuantity;
  @override
  @JsonKey(name: 'correction_reason')
  final String? correctionReason;
  @override
  @JsonKey(name: 'line_number')
  final int? lineNumber;
  final Map<String, dynamic>? _boundingBox;
  @override
  @JsonKey(name: 'bounding_box')
  Map<String, dynamic>? get boundingBox {
    final value = _boundingBox;
    if (value == null) return null;
    if (_boundingBox is EqualUnmodifiableMapView) return _boundingBox;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @override
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;
// Related data (not serialized - runtime only)
  @override
  @JsonKey(ignore: true)
  final Product? matchedProduct;
  @override
  @JsonKey(ignore: true)
  final Brand? matchedBrand;
  @override
  @JsonKey(ignore: true)
  final BrandVariant? matchedVariant;

  @override
  String toString() {
    return 'OCRExtractedItem(id: $id, sessionId: $sessionId, extractedText: $extractedText, brandText: $brandText, sizeText: $sizeText, quantityText: $quantityText, priceText: $priceText, parsedQuantity: $parsedQuantity, parsedPrice: $parsedPrice, parsedSize: $parsedSize, ratePerUnit: $ratePerUnit, openingStock: $openingStock, closingStock: $closingStock, rowNumber: $rowNumber, matchedProductId: $matchedProductId, matchedBrandId: $matchedBrandId, matchedVariantId: $matchedVariantId, matchConfidence: $matchConfidence, matchMethod: $matchMethod, matchDetails: $matchDetails, isConfirmed: $isConfirmed, isRejected: $isRejected, userCorrectedProductId: $userCorrectedProductId, userCorrectedQuantity: $userCorrectedQuantity, correctionReason: $correctionReason, lineNumber: $lineNumber, boundingBox: $boundingBox, createdAt: $createdAt, updatedAt: $updatedAt, matchedProduct: $matchedProduct, matchedBrand: $matchedBrand, matchedVariant: $matchedVariant)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OCRExtractedItemImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.extractedText, extractedText) ||
                other.extractedText == extractedText) &&
            (identical(other.brandText, brandText) ||
                other.brandText == brandText) &&
            (identical(other.sizeText, sizeText) ||
                other.sizeText == sizeText) &&
            (identical(other.quantityText, quantityText) ||
                other.quantityText == quantityText) &&
            (identical(other.priceText, priceText) ||
                other.priceText == priceText) &&
            (identical(other.parsedQuantity, parsedQuantity) ||
                other.parsedQuantity == parsedQuantity) &&
            (identical(other.parsedPrice, parsedPrice) ||
                other.parsedPrice == parsedPrice) &&
            (identical(other.parsedSize, parsedSize) ||
                other.parsedSize == parsedSize) &&
            (identical(other.ratePerUnit, ratePerUnit) ||
                other.ratePerUnit == ratePerUnit) &&
            (identical(other.openingStock, openingStock) ||
                other.openingStock == openingStock) &&
            (identical(other.closingStock, closingStock) ||
                other.closingStock == closingStock) &&
            (identical(other.rowNumber, rowNumber) ||
                other.rowNumber == rowNumber) &&
            (identical(other.matchedProductId, matchedProductId) ||
                other.matchedProductId == matchedProductId) &&
            (identical(other.matchedBrandId, matchedBrandId) ||
                other.matchedBrandId == matchedBrandId) &&
            (identical(other.matchedVariantId, matchedVariantId) ||
                other.matchedVariantId == matchedVariantId) &&
            (identical(other.matchConfidence, matchConfidence) ||
                other.matchConfidence == matchConfidence) &&
            (identical(other.matchMethod, matchMethod) ||
                other.matchMethod == matchMethod) &&
            const DeepCollectionEquality()
                .equals(other._matchDetails, _matchDetails) &&
            (identical(other.isConfirmed, isConfirmed) ||
                other.isConfirmed == isConfirmed) &&
            (identical(other.isRejected, isRejected) ||
                other.isRejected == isRejected) &&
            (identical(other.userCorrectedProductId, userCorrectedProductId) ||
                other.userCorrectedProductId == userCorrectedProductId) &&
            (identical(other.userCorrectedQuantity, userCorrectedQuantity) ||
                other.userCorrectedQuantity == userCorrectedQuantity) &&
            (identical(other.correctionReason, correctionReason) ||
                other.correctionReason == correctionReason) &&
            (identical(other.lineNumber, lineNumber) ||
                other.lineNumber == lineNumber) &&
            const DeepCollectionEquality()
                .equals(other._boundingBox, _boundingBox) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.matchedProduct, matchedProduct) ||
                other.matchedProduct == matchedProduct) &&
            (identical(other.matchedBrand, matchedBrand) ||
                other.matchedBrand == matchedBrand) &&
            (identical(other.matchedVariant, matchedVariant) ||
                other.matchedVariant == matchedVariant));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        sessionId,
        extractedText,
        brandText,
        sizeText,
        quantityText,
        priceText,
        parsedQuantity,
        parsedPrice,
        parsedSize,
        ratePerUnit,
        openingStock,
        closingStock,
        rowNumber,
        matchedProductId,
        matchedBrandId,
        matchedVariantId,
        matchConfidence,
        matchMethod,
        const DeepCollectionEquality().hash(_matchDetails),
        isConfirmed,
        isRejected,
        userCorrectedProductId,
        userCorrectedQuantity,
        correctionReason,
        lineNumber,
        const DeepCollectionEquality().hash(_boundingBox),
        createdAt,
        updatedAt,
        matchedProduct,
        matchedBrand,
        matchedVariant
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$OCRExtractedItemImplCopyWith<_$OCRExtractedItemImpl> get copyWith =>
      __$$OCRExtractedItemImplCopyWithImpl<_$OCRExtractedItemImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OCRExtractedItemImplToJson(
      this,
    );
  }
}

abstract class _OCRExtractedItem implements OCRExtractedItem {
  const factory _OCRExtractedItem(
      {required final String id,
      @JsonKey(name: 'session_id') required final String sessionId,
      @JsonKey(name: 'extracted_text') required final String extractedText,
      @JsonKey(name: 'brand_text') final String? brandText,
      @JsonKey(name: 'size_text') final String? sizeText,
      @JsonKey(name: 'quantity_text') final String? quantityText,
      @JsonKey(name: 'price_text') final String? priceText,
      @JsonKey(name: 'parsed_quantity') final int? parsedQuantity,
      @JsonKey(name: 'parsed_price') final double? parsedPrice,
      @JsonKey(name: 'parsed_size') final String? parsedSize,
      @JsonKey(name: 'rate_per_unit') final double? ratePerUnit,
      @JsonKey(name: 'opening_stock') final int? openingStock,
      @JsonKey(name: 'closing_stock') final int? closingStock,
      @JsonKey(name: 'row_number') final int? rowNumber,
      @JsonKey(name: 'matched_product_id') final String? matchedProductId,
      @JsonKey(name: 'matched_brand_id') final String? matchedBrandId,
      @JsonKey(name: 'matched_variant_id') final String? matchedVariantId,
      @JsonKey(name: 'match_confidence') required final double matchConfidence,
      @JsonKey(name: 'match_method') final String? matchMethod,
      @JsonKey(name: 'match_details') final Map<String, dynamic>? matchDetails,
      @JsonKey(name: 'is_confirmed') final bool isConfirmed,
      @JsonKey(name: 'is_rejected') final bool isRejected,
      @JsonKey(name: 'user_corrected_product_id')
      final String? userCorrectedProductId,
      @JsonKey(name: 'user_corrected_quantity')
      final int? userCorrectedQuantity,
      @JsonKey(name: 'correction_reason') final String? correctionReason,
      @JsonKey(name: 'line_number') final int? lineNumber,
      @JsonKey(name: 'bounding_box') final Map<String, dynamic>? boundingBox,
      @JsonKey(name: 'created_at') required final DateTime createdAt,
      @JsonKey(name: 'updated_at') required final DateTime updatedAt,
      @JsonKey(ignore: true) final Product? matchedProduct,
      @JsonKey(ignore: true) final Brand? matchedBrand,
      @JsonKey(ignore: true)
      final BrandVariant? matchedVariant}) = _$OCRExtractedItemImpl;

  factory _OCRExtractedItem.fromJson(Map<String, dynamic> json) =
      _$OCRExtractedItemImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'session_id')
  String get sessionId;
  @override
  @JsonKey(name: 'extracted_text')
  String get extractedText;
  @override
  @JsonKey(name: 'brand_text')
  String? get brandText;
  @override
  @JsonKey(name: 'size_text')
  String? get sizeText;
  @override
  @JsonKey(name: 'quantity_text')
  String? get quantityText;
  @override
  @JsonKey(name: 'price_text')
  String? get priceText;
  @override
  @JsonKey(name: 'parsed_quantity')
  int? get parsedQuantity;
  @override
  @JsonKey(name: 'parsed_price')
  double? get parsedPrice;
  @override
  @JsonKey(name: 'parsed_size')
  String? get parsedSize;
  @override // Stock tracking fields
  @JsonKey(name: 'rate_per_unit')
  double? get ratePerUnit;
  @override
  @JsonKey(name: 'opening_stock')
  int? get openingStock;
  @override
  @JsonKey(name: 'closing_stock')
  int? get closingStock;
  @override
  @JsonKey(name: 'row_number')
  int? get rowNumber;
  @override
  @JsonKey(name: 'matched_product_id')
  String? get matchedProductId;
  @override
  @JsonKey(name: 'matched_brand_id')
  String? get matchedBrandId;
  @override
  @JsonKey(name: 'matched_variant_id')
  String? get matchedVariantId;
  @override
  @JsonKey(name: 'match_confidence')
  double get matchConfidence;
  @override
  @JsonKey(name: 'match_method')
  String? get matchMethod;
  @override
  @JsonKey(name: 'match_details')
  Map<String, dynamic>? get matchDetails;
  @override
  @JsonKey(name: 'is_confirmed')
  bool get isConfirmed;
  @override
  @JsonKey(name: 'is_rejected')
  bool get isRejected;
  @override
  @JsonKey(name: 'user_corrected_product_id')
  String? get userCorrectedProductId;
  @override
  @JsonKey(name: 'user_corrected_quantity')
  int? get userCorrectedQuantity;
  @override
  @JsonKey(name: 'correction_reason')
  String? get correctionReason;
  @override
  @JsonKey(name: 'line_number')
  int? get lineNumber;
  @override
  @JsonKey(name: 'bounding_box')
  Map<String, dynamic>? get boundingBox;
  @override
  @JsonKey(name: 'created_at')
  DateTime get createdAt;
  @override
  @JsonKey(name: 'updated_at')
  DateTime get updatedAt;
  @override // Related data (not serialized - runtime only)
  @JsonKey(ignore: true)
  Product? get matchedProduct;
  @override
  @JsonKey(ignore: true)
  Brand? get matchedBrand;
  @override
  @JsonKey(ignore: true)
  BrandVariant? get matchedVariant;
  @override
  @JsonKey(ignore: true)
  _$$OCRExtractedItemImplCopyWith<_$OCRExtractedItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

BrandAlias _$BrandAliasFromJson(Map<String, dynamic> json) {
  return _BrandAlias.fromJson(json);
}

/// @nodoc
mixin _$BrandAlias {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'tenant_id')
  String get tenantId => throw _privateConstructorUsedError;
  @JsonKey(name: 'brand_id')
  String get brandId => throw _privateConstructorUsedError;
  @JsonKey(name: 'alias_text')
  String get aliasText => throw _privateConstructorUsedError;
  @JsonKey(name: 'alias_type')
  String get aliasType => throw _privateConstructorUsedError;
  @JsonKey(name: 'match_count')
  int get matchCount => throw _privateConstructorUsedError;
  @JsonKey(name: 'last_matched_at')
  DateTime? get lastMatchedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_active')
  bool get isActive => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_by')
  String? get createdBy => throw _privateConstructorUsedError;
  @JsonKey(name: 'approved_by')
  String? get approvedBy => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'updated_at')
  DateTime get updatedAt => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  Brand? get brand => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BrandAliasCopyWith<BrandAlias> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BrandAliasCopyWith<$Res> {
  factory $BrandAliasCopyWith(
          BrandAlias value, $Res Function(BrandAlias) then) =
      _$BrandAliasCopyWithImpl<$Res, BrandAlias>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'tenant_id') String tenantId,
      @JsonKey(name: 'brand_id') String brandId,
      @JsonKey(name: 'alias_text') String aliasText,
      @JsonKey(name: 'alias_type') String aliasType,
      @JsonKey(name: 'match_count') int matchCount,
      @JsonKey(name: 'last_matched_at') DateTime? lastMatchedAt,
      @JsonKey(name: 'is_active') bool isActive,
      @JsonKey(name: 'created_by') String? createdBy,
      @JsonKey(name: 'approved_by') String? approvedBy,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'updated_at') DateTime updatedAt,
      @JsonKey(ignore: true) Brand? brand});
}

/// @nodoc
class _$BrandAliasCopyWithImpl<$Res, $Val extends BrandAlias>
    implements $BrandAliasCopyWith<$Res> {
  _$BrandAliasCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? tenantId = null,
    Object? brandId = null,
    Object? aliasText = null,
    Object? aliasType = null,
    Object? matchCount = null,
    Object? lastMatchedAt = freezed,
    Object? isActive = null,
    Object? createdBy = freezed,
    Object? approvedBy = freezed,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? brand = freezed,
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
      brandId: null == brandId
          ? _value.brandId
          : brandId // ignore: cast_nullable_to_non_nullable
              as String,
      aliasText: null == aliasText
          ? _value.aliasText
          : aliasText // ignore: cast_nullable_to_non_nullable
              as String,
      aliasType: null == aliasType
          ? _value.aliasType
          : aliasType // ignore: cast_nullable_to_non_nullable
              as String,
      matchCount: null == matchCount
          ? _value.matchCount
          : matchCount // ignore: cast_nullable_to_non_nullable
              as int,
      lastMatchedAt: freezed == lastMatchedAt
          ? _value.lastMatchedAt
          : lastMatchedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool,
      createdBy: freezed == createdBy
          ? _value.createdBy
          : createdBy // ignore: cast_nullable_to_non_nullable
              as String?,
      approvedBy: freezed == approvedBy
          ? _value.approvedBy
          : approvedBy // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      brand: freezed == brand
          ? _value.brand
          : brand // ignore: cast_nullable_to_non_nullable
              as Brand?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BrandAliasImplCopyWith<$Res>
    implements $BrandAliasCopyWith<$Res> {
  factory _$$BrandAliasImplCopyWith(
          _$BrandAliasImpl value, $Res Function(_$BrandAliasImpl) then) =
      __$$BrandAliasImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'tenant_id') String tenantId,
      @JsonKey(name: 'brand_id') String brandId,
      @JsonKey(name: 'alias_text') String aliasText,
      @JsonKey(name: 'alias_type') String aliasType,
      @JsonKey(name: 'match_count') int matchCount,
      @JsonKey(name: 'last_matched_at') DateTime? lastMatchedAt,
      @JsonKey(name: 'is_active') bool isActive,
      @JsonKey(name: 'created_by') String? createdBy,
      @JsonKey(name: 'approved_by') String? approvedBy,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'updated_at') DateTime updatedAt,
      @JsonKey(ignore: true) Brand? brand});
}

/// @nodoc
class __$$BrandAliasImplCopyWithImpl<$Res>
    extends _$BrandAliasCopyWithImpl<$Res, _$BrandAliasImpl>
    implements _$$BrandAliasImplCopyWith<$Res> {
  __$$BrandAliasImplCopyWithImpl(
      _$BrandAliasImpl _value, $Res Function(_$BrandAliasImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? tenantId = null,
    Object? brandId = null,
    Object? aliasText = null,
    Object? aliasType = null,
    Object? matchCount = null,
    Object? lastMatchedAt = freezed,
    Object? isActive = null,
    Object? createdBy = freezed,
    Object? approvedBy = freezed,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? brand = freezed,
  }) {
    return _then(_$BrandAliasImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      tenantId: null == tenantId
          ? _value.tenantId
          : tenantId // ignore: cast_nullable_to_non_nullable
              as String,
      brandId: null == brandId
          ? _value.brandId
          : brandId // ignore: cast_nullable_to_non_nullable
              as String,
      aliasText: null == aliasText
          ? _value.aliasText
          : aliasText // ignore: cast_nullable_to_non_nullable
              as String,
      aliasType: null == aliasType
          ? _value.aliasType
          : aliasType // ignore: cast_nullable_to_non_nullable
              as String,
      matchCount: null == matchCount
          ? _value.matchCount
          : matchCount // ignore: cast_nullable_to_non_nullable
              as int,
      lastMatchedAt: freezed == lastMatchedAt
          ? _value.lastMatchedAt
          : lastMatchedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool,
      createdBy: freezed == createdBy
          ? _value.createdBy
          : createdBy // ignore: cast_nullable_to_non_nullable
              as String?,
      approvedBy: freezed == approvedBy
          ? _value.approvedBy
          : approvedBy // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      brand: freezed == brand
          ? _value.brand
          : brand // ignore: cast_nullable_to_non_nullable
              as Brand?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BrandAliasImpl implements _BrandAlias {
  const _$BrandAliasImpl(
      {required this.id,
      @JsonKey(name: 'tenant_id') required this.tenantId,
      @JsonKey(name: 'brand_id') required this.brandId,
      @JsonKey(name: 'alias_text') required this.aliasText,
      @JsonKey(name: 'alias_type') required this.aliasType,
      @JsonKey(name: 'match_count') this.matchCount = 0,
      @JsonKey(name: 'last_matched_at') this.lastMatchedAt,
      @JsonKey(name: 'is_active') this.isActive = true,
      @JsonKey(name: 'created_by') this.createdBy,
      @JsonKey(name: 'approved_by') this.approvedBy,
      @JsonKey(name: 'created_at') required this.createdAt,
      @JsonKey(name: 'updated_at') required this.updatedAt,
      @JsonKey(ignore: true) this.brand});

  factory _$BrandAliasImpl.fromJson(Map<String, dynamic> json) =>
      _$$BrandAliasImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'tenant_id')
  final String tenantId;
  @override
  @JsonKey(name: 'brand_id')
  final String brandId;
  @override
  @JsonKey(name: 'alias_text')
  final String aliasText;
  @override
  @JsonKey(name: 'alias_type')
  final String aliasType;
  @override
  @JsonKey(name: 'match_count')
  final int matchCount;
  @override
  @JsonKey(name: 'last_matched_at')
  final DateTime? lastMatchedAt;
  @override
  @JsonKey(name: 'is_active')
  final bool isActive;
  @override
  @JsonKey(name: 'created_by')
  final String? createdBy;
  @override
  @JsonKey(name: 'approved_by')
  final String? approvedBy;
  @override
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @override
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;
  @override
  @JsonKey(ignore: true)
  final Brand? brand;

  @override
  String toString() {
    return 'BrandAlias(id: $id, tenantId: $tenantId, brandId: $brandId, aliasText: $aliasText, aliasType: $aliasType, matchCount: $matchCount, lastMatchedAt: $lastMatchedAt, isActive: $isActive, createdBy: $createdBy, approvedBy: $approvedBy, createdAt: $createdAt, updatedAt: $updatedAt, brand: $brand)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BrandAliasImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.tenantId, tenantId) ||
                other.tenantId == tenantId) &&
            (identical(other.brandId, brandId) || other.brandId == brandId) &&
            (identical(other.aliasText, aliasText) ||
                other.aliasText == aliasText) &&
            (identical(other.aliasType, aliasType) ||
                other.aliasType == aliasType) &&
            (identical(other.matchCount, matchCount) ||
                other.matchCount == matchCount) &&
            (identical(other.lastMatchedAt, lastMatchedAt) ||
                other.lastMatchedAt == lastMatchedAt) &&
            (identical(other.isActive, isActive) ||
                other.isActive == isActive) &&
            (identical(other.createdBy, createdBy) ||
                other.createdBy == createdBy) &&
            (identical(other.approvedBy, approvedBy) ||
                other.approvedBy == approvedBy) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.brand, brand) || other.brand == brand));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      tenantId,
      brandId,
      aliasText,
      aliasType,
      matchCount,
      lastMatchedAt,
      isActive,
      createdBy,
      approvedBy,
      createdAt,
      updatedAt,
      brand);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BrandAliasImplCopyWith<_$BrandAliasImpl> get copyWith =>
      __$$BrandAliasImplCopyWithImpl<_$BrandAliasImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BrandAliasImplToJson(
      this,
    );
  }
}

abstract class _BrandAlias implements BrandAlias {
  const factory _BrandAlias(
      {required final String id,
      @JsonKey(name: 'tenant_id') required final String tenantId,
      @JsonKey(name: 'brand_id') required final String brandId,
      @JsonKey(name: 'alias_text') required final String aliasText,
      @JsonKey(name: 'alias_type') required final String aliasType,
      @JsonKey(name: 'match_count') final int matchCount,
      @JsonKey(name: 'last_matched_at') final DateTime? lastMatchedAt,
      @JsonKey(name: 'is_active') final bool isActive,
      @JsonKey(name: 'created_by') final String? createdBy,
      @JsonKey(name: 'approved_by') final String? approvedBy,
      @JsonKey(name: 'created_at') required final DateTime createdAt,
      @JsonKey(name: 'updated_at') required final DateTime updatedAt,
      @JsonKey(ignore: true) final Brand? brand}) = _$BrandAliasImpl;

  factory _BrandAlias.fromJson(Map<String, dynamic> json) =
      _$BrandAliasImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'tenant_id')
  String get tenantId;
  @override
  @JsonKey(name: 'brand_id')
  String get brandId;
  @override
  @JsonKey(name: 'alias_text')
  String get aliasText;
  @override
  @JsonKey(name: 'alias_type')
  String get aliasType;
  @override
  @JsonKey(name: 'match_count')
  int get matchCount;
  @override
  @JsonKey(name: 'last_matched_at')
  DateTime? get lastMatchedAt;
  @override
  @JsonKey(name: 'is_active')
  bool get isActive;
  @override
  @JsonKey(name: 'created_by')
  String? get createdBy;
  @override
  @JsonKey(name: 'approved_by')
  String? get approvedBy;
  @override
  @JsonKey(name: 'created_at')
  DateTime get createdAt;
  @override
  @JsonKey(name: 'updated_at')
  DateTime get updatedAt;
  @override
  @JsonKey(ignore: true)
  Brand? get brand;
  @override
  @JsonKey(ignore: true)
  _$$BrandAliasImplCopyWith<_$BrandAliasImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

OCRSessionResponse _$OCRSessionResponseFromJson(Map<String, dynamic> json) {
  return _OCRSessionResponse.fromJson(json);
}

/// @nodoc
mixin _$OCRSessionResponse {
  OCRSession get session => throw _privateConstructorUsedError;
  @JsonKey(name: 'extracted_items')
  List<OCRExtractedItem> get extractedItems =>
      throw _privateConstructorUsedError;
  OCRProcessingSummary? get summary => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $OCRSessionResponseCopyWith<OCRSessionResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OCRSessionResponseCopyWith<$Res> {
  factory $OCRSessionResponseCopyWith(
          OCRSessionResponse value, $Res Function(OCRSessionResponse) then) =
      _$OCRSessionResponseCopyWithImpl<$Res, OCRSessionResponse>;
  @useResult
  $Res call(
      {OCRSession session,
      @JsonKey(name: 'extracted_items') List<OCRExtractedItem> extractedItems,
      OCRProcessingSummary? summary});

  $OCRSessionCopyWith<$Res> get session;
  $OCRProcessingSummaryCopyWith<$Res>? get summary;
}

/// @nodoc
class _$OCRSessionResponseCopyWithImpl<$Res, $Val extends OCRSessionResponse>
    implements $OCRSessionResponseCopyWith<$Res> {
  _$OCRSessionResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? session = null,
    Object? extractedItems = null,
    Object? summary = freezed,
  }) {
    return _then(_value.copyWith(
      session: null == session
          ? _value.session
          : session // ignore: cast_nullable_to_non_nullable
              as OCRSession,
      extractedItems: null == extractedItems
          ? _value.extractedItems
          : extractedItems // ignore: cast_nullable_to_non_nullable
              as List<OCRExtractedItem>,
      summary: freezed == summary
          ? _value.summary
          : summary // ignore: cast_nullable_to_non_nullable
              as OCRProcessingSummary?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $OCRSessionCopyWith<$Res> get session {
    return $OCRSessionCopyWith<$Res>(_value.session, (value) {
      return _then(_value.copyWith(session: value) as $Val);
    });
  }

  @override
  @pragma('vm:prefer-inline')
  $OCRProcessingSummaryCopyWith<$Res>? get summary {
    if (_value.summary == null) {
      return null;
    }

    return $OCRProcessingSummaryCopyWith<$Res>(_value.summary!, (value) {
      return _then(_value.copyWith(summary: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$OCRSessionResponseImplCopyWith<$Res>
    implements $OCRSessionResponseCopyWith<$Res> {
  factory _$$OCRSessionResponseImplCopyWith(_$OCRSessionResponseImpl value,
          $Res Function(_$OCRSessionResponseImpl) then) =
      __$$OCRSessionResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {OCRSession session,
      @JsonKey(name: 'extracted_items') List<OCRExtractedItem> extractedItems,
      OCRProcessingSummary? summary});

  @override
  $OCRSessionCopyWith<$Res> get session;
  @override
  $OCRProcessingSummaryCopyWith<$Res>? get summary;
}

/// @nodoc
class __$$OCRSessionResponseImplCopyWithImpl<$Res>
    extends _$OCRSessionResponseCopyWithImpl<$Res, _$OCRSessionResponseImpl>
    implements _$$OCRSessionResponseImplCopyWith<$Res> {
  __$$OCRSessionResponseImplCopyWithImpl(_$OCRSessionResponseImpl _value,
      $Res Function(_$OCRSessionResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? session = null,
    Object? extractedItems = null,
    Object? summary = freezed,
  }) {
    return _then(_$OCRSessionResponseImpl(
      session: null == session
          ? _value.session
          : session // ignore: cast_nullable_to_non_nullable
              as OCRSession,
      extractedItems: null == extractedItems
          ? _value._extractedItems
          : extractedItems // ignore: cast_nullable_to_non_nullable
              as List<OCRExtractedItem>,
      summary: freezed == summary
          ? _value.summary
          : summary // ignore: cast_nullable_to_non_nullable
              as OCRProcessingSummary?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OCRSessionResponseImpl implements _OCRSessionResponse {
  const _$OCRSessionResponseImpl(
      {required this.session,
      @JsonKey(name: 'extracted_items')
      final List<OCRExtractedItem> extractedItems = const [],
      this.summary})
      : _extractedItems = extractedItems;

  factory _$OCRSessionResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$OCRSessionResponseImplFromJson(json);

  @override
  final OCRSession session;
  final List<OCRExtractedItem> _extractedItems;
  @override
  @JsonKey(name: 'extracted_items')
  List<OCRExtractedItem> get extractedItems {
    if (_extractedItems is EqualUnmodifiableListView) return _extractedItems;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_extractedItems);
  }

  @override
  final OCRProcessingSummary? summary;

  @override
  String toString() {
    return 'OCRSessionResponse(session: $session, extractedItems: $extractedItems, summary: $summary)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OCRSessionResponseImpl &&
            (identical(other.session, session) || other.session == session) &&
            const DeepCollectionEquality()
                .equals(other._extractedItems, _extractedItems) &&
            (identical(other.summary, summary) || other.summary == summary));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, session,
      const DeepCollectionEquality().hash(_extractedItems), summary);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$OCRSessionResponseImplCopyWith<_$OCRSessionResponseImpl> get copyWith =>
      __$$OCRSessionResponseImplCopyWithImpl<_$OCRSessionResponseImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OCRSessionResponseImplToJson(
      this,
    );
  }
}

abstract class _OCRSessionResponse implements OCRSessionResponse {
  const factory _OCRSessionResponse(
      {required final OCRSession session,
      @JsonKey(name: 'extracted_items')
      final List<OCRExtractedItem> extractedItems,
      final OCRProcessingSummary? summary}) = _$OCRSessionResponseImpl;

  factory _OCRSessionResponse.fromJson(Map<String, dynamic> json) =
      _$OCRSessionResponseImpl.fromJson;

  @override
  OCRSession get session;
  @override
  @JsonKey(name: 'extracted_items')
  List<OCRExtractedItem> get extractedItems;
  @override
  OCRProcessingSummary? get summary;
  @override
  @JsonKey(ignore: true)
  _$$OCRSessionResponseImplCopyWith<_$OCRSessionResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

OCRProcessingSummary _$OCRProcessingSummaryFromJson(Map<String, dynamic> json) {
  return _OCRProcessingSummary.fromJson(json);
}

/// @nodoc
mixin _$OCRProcessingSummary {
  @JsonKey(name: 'total_items')
  int get totalItems => throw _privateConstructorUsedError;
  @JsonKey(name: 'matched_items')
  int get matchedItems => throw _privateConstructorUsedError;
  @JsonKey(name: 'unmatched_items')
  int get unmatchedItems => throw _privateConstructorUsedError;
  @JsonKey(name: 'confidence_avg')
  double get confidenceAvg => throw _privateConstructorUsedError;
  @JsonKey(name: 'processing_time_ms')
  int get processingTimeMs => throw _privateConstructorUsedError;
  @JsonKey(name: 'requires_review')
  bool get requiresReview => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $OCRProcessingSummaryCopyWith<OCRProcessingSummary> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OCRProcessingSummaryCopyWith<$Res> {
  factory $OCRProcessingSummaryCopyWith(OCRProcessingSummary value,
          $Res Function(OCRProcessingSummary) then) =
      _$OCRProcessingSummaryCopyWithImpl<$Res, OCRProcessingSummary>;
  @useResult
  $Res call(
      {@JsonKey(name: 'total_items') int totalItems,
      @JsonKey(name: 'matched_items') int matchedItems,
      @JsonKey(name: 'unmatched_items') int unmatchedItems,
      @JsonKey(name: 'confidence_avg') double confidenceAvg,
      @JsonKey(name: 'processing_time_ms') int processingTimeMs,
      @JsonKey(name: 'requires_review') bool requiresReview});
}

/// @nodoc
class _$OCRProcessingSummaryCopyWithImpl<$Res,
        $Val extends OCRProcessingSummary>
    implements $OCRProcessingSummaryCopyWith<$Res> {
  _$OCRProcessingSummaryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? totalItems = null,
    Object? matchedItems = null,
    Object? unmatchedItems = null,
    Object? confidenceAvg = null,
    Object? processingTimeMs = null,
    Object? requiresReview = null,
  }) {
    return _then(_value.copyWith(
      totalItems: null == totalItems
          ? _value.totalItems
          : totalItems // ignore: cast_nullable_to_non_nullable
              as int,
      matchedItems: null == matchedItems
          ? _value.matchedItems
          : matchedItems // ignore: cast_nullable_to_non_nullable
              as int,
      unmatchedItems: null == unmatchedItems
          ? _value.unmatchedItems
          : unmatchedItems // ignore: cast_nullable_to_non_nullable
              as int,
      confidenceAvg: null == confidenceAvg
          ? _value.confidenceAvg
          : confidenceAvg // ignore: cast_nullable_to_non_nullable
              as double,
      processingTimeMs: null == processingTimeMs
          ? _value.processingTimeMs
          : processingTimeMs // ignore: cast_nullable_to_non_nullable
              as int,
      requiresReview: null == requiresReview
          ? _value.requiresReview
          : requiresReview // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OCRProcessingSummaryImplCopyWith<$Res>
    implements $OCRProcessingSummaryCopyWith<$Res> {
  factory _$$OCRProcessingSummaryImplCopyWith(_$OCRProcessingSummaryImpl value,
          $Res Function(_$OCRProcessingSummaryImpl) then) =
      __$$OCRProcessingSummaryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'total_items') int totalItems,
      @JsonKey(name: 'matched_items') int matchedItems,
      @JsonKey(name: 'unmatched_items') int unmatchedItems,
      @JsonKey(name: 'confidence_avg') double confidenceAvg,
      @JsonKey(name: 'processing_time_ms') int processingTimeMs,
      @JsonKey(name: 'requires_review') bool requiresReview});
}

/// @nodoc
class __$$OCRProcessingSummaryImplCopyWithImpl<$Res>
    extends _$OCRProcessingSummaryCopyWithImpl<$Res, _$OCRProcessingSummaryImpl>
    implements _$$OCRProcessingSummaryImplCopyWith<$Res> {
  __$$OCRProcessingSummaryImplCopyWithImpl(_$OCRProcessingSummaryImpl _value,
      $Res Function(_$OCRProcessingSummaryImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? totalItems = null,
    Object? matchedItems = null,
    Object? unmatchedItems = null,
    Object? confidenceAvg = null,
    Object? processingTimeMs = null,
    Object? requiresReview = null,
  }) {
    return _then(_$OCRProcessingSummaryImpl(
      totalItems: null == totalItems
          ? _value.totalItems
          : totalItems // ignore: cast_nullable_to_non_nullable
              as int,
      matchedItems: null == matchedItems
          ? _value.matchedItems
          : matchedItems // ignore: cast_nullable_to_non_nullable
              as int,
      unmatchedItems: null == unmatchedItems
          ? _value.unmatchedItems
          : unmatchedItems // ignore: cast_nullable_to_non_nullable
              as int,
      confidenceAvg: null == confidenceAvg
          ? _value.confidenceAvg
          : confidenceAvg // ignore: cast_nullable_to_non_nullable
              as double,
      processingTimeMs: null == processingTimeMs
          ? _value.processingTimeMs
          : processingTimeMs // ignore: cast_nullable_to_non_nullable
              as int,
      requiresReview: null == requiresReview
          ? _value.requiresReview
          : requiresReview // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OCRProcessingSummaryImpl implements _OCRProcessingSummary {
  const _$OCRProcessingSummaryImpl(
      {@JsonKey(name: 'total_items') required this.totalItems,
      @JsonKey(name: 'matched_items') required this.matchedItems,
      @JsonKey(name: 'unmatched_items') required this.unmatchedItems,
      @JsonKey(name: 'confidence_avg') required this.confidenceAvg,
      @JsonKey(name: 'processing_time_ms') required this.processingTimeMs,
      @JsonKey(name: 'requires_review') required this.requiresReview});

  factory _$OCRProcessingSummaryImpl.fromJson(Map<String, dynamic> json) =>
      _$$OCRProcessingSummaryImplFromJson(json);

  @override
  @JsonKey(name: 'total_items')
  final int totalItems;
  @override
  @JsonKey(name: 'matched_items')
  final int matchedItems;
  @override
  @JsonKey(name: 'unmatched_items')
  final int unmatchedItems;
  @override
  @JsonKey(name: 'confidence_avg')
  final double confidenceAvg;
  @override
  @JsonKey(name: 'processing_time_ms')
  final int processingTimeMs;
  @override
  @JsonKey(name: 'requires_review')
  final bool requiresReview;

  @override
  String toString() {
    return 'OCRProcessingSummary(totalItems: $totalItems, matchedItems: $matchedItems, unmatchedItems: $unmatchedItems, confidenceAvg: $confidenceAvg, processingTimeMs: $processingTimeMs, requiresReview: $requiresReview)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OCRProcessingSummaryImpl &&
            (identical(other.totalItems, totalItems) ||
                other.totalItems == totalItems) &&
            (identical(other.matchedItems, matchedItems) ||
                other.matchedItems == matchedItems) &&
            (identical(other.unmatchedItems, unmatchedItems) ||
                other.unmatchedItems == unmatchedItems) &&
            (identical(other.confidenceAvg, confidenceAvg) ||
                other.confidenceAvg == confidenceAvg) &&
            (identical(other.processingTimeMs, processingTimeMs) ||
                other.processingTimeMs == processingTimeMs) &&
            (identical(other.requiresReview, requiresReview) ||
                other.requiresReview == requiresReview));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, totalItems, matchedItems,
      unmatchedItems, confidenceAvg, processingTimeMs, requiresReview);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$OCRProcessingSummaryImplCopyWith<_$OCRProcessingSummaryImpl>
      get copyWith =>
          __$$OCRProcessingSummaryImplCopyWithImpl<_$OCRProcessingSummaryImpl>(
              this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OCRProcessingSummaryImplToJson(
      this,
    );
  }
}

abstract class _OCRProcessingSummary implements OCRProcessingSummary {
  const factory _OCRProcessingSummary(
      {@JsonKey(name: 'total_items') required final int totalItems,
      @JsonKey(name: 'matched_items') required final int matchedItems,
      @JsonKey(name: 'unmatched_items') required final int unmatchedItems,
      @JsonKey(name: 'confidence_avg') required final double confidenceAvg,
      @JsonKey(name: 'processing_time_ms') required final int processingTimeMs,
      @JsonKey(name: 'requires_review')
      required final bool requiresReview}) = _$OCRProcessingSummaryImpl;

  factory _OCRProcessingSummary.fromJson(Map<String, dynamic> json) =
      _$OCRProcessingSummaryImpl.fromJson;

  @override
  @JsonKey(name: 'total_items')
  int get totalItems;
  @override
  @JsonKey(name: 'matched_items')
  int get matchedItems;
  @override
  @JsonKey(name: 'unmatched_items')
  int get unmatchedItems;
  @override
  @JsonKey(name: 'confidence_avg')
  double get confidenceAvg;
  @override
  @JsonKey(name: 'processing_time_ms')
  int get processingTimeMs;
  @override
  @JsonKey(name: 'requires_review')
  bool get requiresReview;
  @override
  @JsonKey(ignore: true)
  _$$OCRProcessingSummaryImplCopyWith<_$OCRProcessingSummaryImpl>
      get copyWith => throw _privateConstructorUsedError;
}

CreateOCRSessionRequest _$CreateOCRSessionRequestFromJson(
    Map<String, dynamic> json) {
  return _CreateOCRSessionRequest.fromJson(json);
}

/// @nodoc
mixin _$CreateOCRSessionRequest {
  @JsonKey(name: 'image_data')
  String get imageData => throw _privateConstructorUsedError;
  @JsonKey(name: 'image_type')
  String get imageType => throw _privateConstructorUsedError;
  @JsonKey(name: 'session_type')
  String get sessionType => throw _privateConstructorUsedError;
  @JsonKey(name: 'shop_id')
  String get shopId => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $CreateOCRSessionRequestCopyWith<CreateOCRSessionRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CreateOCRSessionRequestCopyWith<$Res> {
  factory $CreateOCRSessionRequestCopyWith(CreateOCRSessionRequest value,
          $Res Function(CreateOCRSessionRequest) then) =
      _$CreateOCRSessionRequestCopyWithImpl<$Res, CreateOCRSessionRequest>;
  @useResult
  $Res call(
      {@JsonKey(name: 'image_data') String imageData,
      @JsonKey(name: 'image_type') String imageType,
      @JsonKey(name: 'session_type') String sessionType,
      @JsonKey(name: 'shop_id') String shopId});
}

/// @nodoc
class _$CreateOCRSessionRequestCopyWithImpl<$Res,
        $Val extends CreateOCRSessionRequest>
    implements $CreateOCRSessionRequestCopyWith<$Res> {
  _$CreateOCRSessionRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? imageData = null,
    Object? imageType = null,
    Object? sessionType = null,
    Object? shopId = null,
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
      sessionType: null == sessionType
          ? _value.sessionType
          : sessionType // ignore: cast_nullable_to_non_nullable
              as String,
      shopId: null == shopId
          ? _value.shopId
          : shopId // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CreateOCRSessionRequestImplCopyWith<$Res>
    implements $CreateOCRSessionRequestCopyWith<$Res> {
  factory _$$CreateOCRSessionRequestImplCopyWith(
          _$CreateOCRSessionRequestImpl value,
          $Res Function(_$CreateOCRSessionRequestImpl) then) =
      __$$CreateOCRSessionRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'image_data') String imageData,
      @JsonKey(name: 'image_type') String imageType,
      @JsonKey(name: 'session_type') String sessionType,
      @JsonKey(name: 'shop_id') String shopId});
}

/// @nodoc
class __$$CreateOCRSessionRequestImplCopyWithImpl<$Res>
    extends _$CreateOCRSessionRequestCopyWithImpl<$Res,
        _$CreateOCRSessionRequestImpl>
    implements _$$CreateOCRSessionRequestImplCopyWith<$Res> {
  __$$CreateOCRSessionRequestImplCopyWithImpl(
      _$CreateOCRSessionRequestImpl _value,
      $Res Function(_$CreateOCRSessionRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? imageData = null,
    Object? imageType = null,
    Object? sessionType = null,
    Object? shopId = null,
  }) {
    return _then(_$CreateOCRSessionRequestImpl(
      imageData: null == imageData
          ? _value.imageData
          : imageData // ignore: cast_nullable_to_non_nullable
              as String,
      imageType: null == imageType
          ? _value.imageType
          : imageType // ignore: cast_nullable_to_non_nullable
              as String,
      sessionType: null == sessionType
          ? _value.sessionType
          : sessionType // ignore: cast_nullable_to_non_nullable
              as String,
      shopId: null == shopId
          ? _value.shopId
          : shopId // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CreateOCRSessionRequestImpl implements _CreateOCRSessionRequest {
  const _$CreateOCRSessionRequestImpl(
      {@JsonKey(name: 'image_data') required this.imageData,
      @JsonKey(name: 'image_type') required this.imageType,
      @JsonKey(name: 'session_type') required this.sessionType,
      @JsonKey(name: 'shop_id') required this.shopId});

  factory _$CreateOCRSessionRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$CreateOCRSessionRequestImplFromJson(json);

  @override
  @JsonKey(name: 'image_data')
  final String imageData;
  @override
  @JsonKey(name: 'image_type')
  final String imageType;
  @override
  @JsonKey(name: 'session_type')
  final String sessionType;
  @override
  @JsonKey(name: 'shop_id')
  final String shopId;

  @override
  String toString() {
    return 'CreateOCRSessionRequest(imageData: $imageData, imageType: $imageType, sessionType: $sessionType, shopId: $shopId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CreateOCRSessionRequestImpl &&
            (identical(other.imageData, imageData) ||
                other.imageData == imageData) &&
            (identical(other.imageType, imageType) ||
                other.imageType == imageType) &&
            (identical(other.sessionType, sessionType) ||
                other.sessionType == sessionType) &&
            (identical(other.shopId, shopId) || other.shopId == shopId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, imageData, imageType, sessionType, shopId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CreateOCRSessionRequestImplCopyWith<_$CreateOCRSessionRequestImpl>
      get copyWith => __$$CreateOCRSessionRequestImplCopyWithImpl<
          _$CreateOCRSessionRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CreateOCRSessionRequestImplToJson(
      this,
    );
  }
}

abstract class _CreateOCRSessionRequest implements CreateOCRSessionRequest {
  const factory _CreateOCRSessionRequest(
          {@JsonKey(name: 'image_data') required final String imageData,
          @JsonKey(name: 'image_type') required final String imageType,
          @JsonKey(name: 'session_type') required final String sessionType,
          @JsonKey(name: 'shop_id') required final String shopId}) =
      _$CreateOCRSessionRequestImpl;

  factory _CreateOCRSessionRequest.fromJson(Map<String, dynamic> json) =
      _$CreateOCRSessionRequestImpl.fromJson;

  @override
  @JsonKey(name: 'image_data')
  String get imageData;
  @override
  @JsonKey(name: 'image_type')
  String get imageType;
  @override
  @JsonKey(name: 'session_type')
  String get sessionType;
  @override
  @JsonKey(name: 'shop_id')
  String get shopId;
  @override
  @JsonKey(ignore: true)
  _$$CreateOCRSessionRequestImplCopyWith<_$CreateOCRSessionRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}

ConfirmOCRItemsRequest _$ConfirmOCRItemsRequestFromJson(
    Map<String, dynamic> json) {
  return _ConfirmOCRItemsRequest.fromJson(json);
}

/// @nodoc
mixin _$ConfirmOCRItemsRequest {
  @JsonKey(name: 'session_id')
  String get sessionId => throw _privateConstructorUsedError;
  List<OCRItemConfirmation> get items => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ConfirmOCRItemsRequestCopyWith<ConfirmOCRItemsRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ConfirmOCRItemsRequestCopyWith<$Res> {
  factory $ConfirmOCRItemsRequestCopyWith(ConfirmOCRItemsRequest value,
          $Res Function(ConfirmOCRItemsRequest) then) =
      _$ConfirmOCRItemsRequestCopyWithImpl<$Res, ConfirmOCRItemsRequest>;
  @useResult
  $Res call(
      {@JsonKey(name: 'session_id') String sessionId,
      List<OCRItemConfirmation> items});
}

/// @nodoc
class _$ConfirmOCRItemsRequestCopyWithImpl<$Res,
        $Val extends ConfirmOCRItemsRequest>
    implements $ConfirmOCRItemsRequestCopyWith<$Res> {
  _$ConfirmOCRItemsRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionId = null,
    Object? items = null,
  }) {
    return _then(_value.copyWith(
      sessionId: null == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _value.items
          : items // ignore: cast_nullable_to_non_nullable
              as List<OCRItemConfirmation>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ConfirmOCRItemsRequestImplCopyWith<$Res>
    implements $ConfirmOCRItemsRequestCopyWith<$Res> {
  factory _$$ConfirmOCRItemsRequestImplCopyWith(
          _$ConfirmOCRItemsRequestImpl value,
          $Res Function(_$ConfirmOCRItemsRequestImpl) then) =
      __$$ConfirmOCRItemsRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'session_id') String sessionId,
      List<OCRItemConfirmation> items});
}

/// @nodoc
class __$$ConfirmOCRItemsRequestImplCopyWithImpl<$Res>
    extends _$ConfirmOCRItemsRequestCopyWithImpl<$Res,
        _$ConfirmOCRItemsRequestImpl>
    implements _$$ConfirmOCRItemsRequestImplCopyWith<$Res> {
  __$$ConfirmOCRItemsRequestImplCopyWithImpl(
      _$ConfirmOCRItemsRequestImpl _value,
      $Res Function(_$ConfirmOCRItemsRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionId = null,
    Object? items = null,
  }) {
    return _then(_$ConfirmOCRItemsRequestImpl(
      sessionId: null == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<OCRItemConfirmation>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ConfirmOCRItemsRequestImpl implements _ConfirmOCRItemsRequest {
  const _$ConfirmOCRItemsRequestImpl(
      {@JsonKey(name: 'session_id') required this.sessionId,
      required final List<OCRItemConfirmation> items})
      : _items = items;

  factory _$ConfirmOCRItemsRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$ConfirmOCRItemsRequestImplFromJson(json);

  @override
  @JsonKey(name: 'session_id')
  final String sessionId;
  final List<OCRItemConfirmation> _items;
  @override
  List<OCRItemConfirmation> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  String toString() {
    return 'ConfirmOCRItemsRequest(sessionId: $sessionId, items: $items)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ConfirmOCRItemsRequestImpl &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            const DeepCollectionEquality().equals(other._items, _items));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, sessionId, const DeepCollectionEquality().hash(_items));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ConfirmOCRItemsRequestImplCopyWith<_$ConfirmOCRItemsRequestImpl>
      get copyWith => __$$ConfirmOCRItemsRequestImplCopyWithImpl<
          _$ConfirmOCRItemsRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ConfirmOCRItemsRequestImplToJson(
      this,
    );
  }
}

abstract class _ConfirmOCRItemsRequest implements ConfirmOCRItemsRequest {
  const factory _ConfirmOCRItemsRequest(
          {@JsonKey(name: 'session_id') required final String sessionId,
          required final List<OCRItemConfirmation> items}) =
      _$ConfirmOCRItemsRequestImpl;

  factory _ConfirmOCRItemsRequest.fromJson(Map<String, dynamic> json) =
      _$ConfirmOCRItemsRequestImpl.fromJson;

  @override
  @JsonKey(name: 'session_id')
  String get sessionId;
  @override
  List<OCRItemConfirmation> get items;
  @override
  @JsonKey(ignore: true)
  _$$ConfirmOCRItemsRequestImplCopyWith<_$ConfirmOCRItemsRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}

OCRItemConfirmation _$OCRItemConfirmationFromJson(Map<String, dynamic> json) {
  return _OCRItemConfirmation.fromJson(json);
}

/// @nodoc
mixin _$OCRItemConfirmation {
  @JsonKey(name: 'item_id')
  String get itemId => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_confirmed')
  bool get isConfirmed => throw _privateConstructorUsedError;
  @JsonKey(name: 'product_id')
  String? get productId => throw _privateConstructorUsedError;
  int get quantity => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $OCRItemConfirmationCopyWith<OCRItemConfirmation> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OCRItemConfirmationCopyWith<$Res> {
  factory $OCRItemConfirmationCopyWith(
          OCRItemConfirmation value, $Res Function(OCRItemConfirmation) then) =
      _$OCRItemConfirmationCopyWithImpl<$Res, OCRItemConfirmation>;
  @useResult
  $Res call(
      {@JsonKey(name: 'item_id') String itemId,
      @JsonKey(name: 'is_confirmed') bool isConfirmed,
      @JsonKey(name: 'product_id') String? productId,
      int quantity});
}

/// @nodoc
class _$OCRItemConfirmationCopyWithImpl<$Res, $Val extends OCRItemConfirmation>
    implements $OCRItemConfirmationCopyWith<$Res> {
  _$OCRItemConfirmationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? itemId = null,
    Object? isConfirmed = null,
    Object? productId = freezed,
    Object? quantity = null,
  }) {
    return _then(_value.copyWith(
      itemId: null == itemId
          ? _value.itemId
          : itemId // ignore: cast_nullable_to_non_nullable
              as String,
      isConfirmed: null == isConfirmed
          ? _value.isConfirmed
          : isConfirmed // ignore: cast_nullable_to_non_nullable
              as bool,
      productId: freezed == productId
          ? _value.productId
          : productId // ignore: cast_nullable_to_non_nullable
              as String?,
      quantity: null == quantity
          ? _value.quantity
          : quantity // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OCRItemConfirmationImplCopyWith<$Res>
    implements $OCRItemConfirmationCopyWith<$Res> {
  factory _$$OCRItemConfirmationImplCopyWith(_$OCRItemConfirmationImpl value,
          $Res Function(_$OCRItemConfirmationImpl) then) =
      __$$OCRItemConfirmationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'item_id') String itemId,
      @JsonKey(name: 'is_confirmed') bool isConfirmed,
      @JsonKey(name: 'product_id') String? productId,
      int quantity});
}

/// @nodoc
class __$$OCRItemConfirmationImplCopyWithImpl<$Res>
    extends _$OCRItemConfirmationCopyWithImpl<$Res, _$OCRItemConfirmationImpl>
    implements _$$OCRItemConfirmationImplCopyWith<$Res> {
  __$$OCRItemConfirmationImplCopyWithImpl(_$OCRItemConfirmationImpl _value,
      $Res Function(_$OCRItemConfirmationImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? itemId = null,
    Object? isConfirmed = null,
    Object? productId = freezed,
    Object? quantity = null,
  }) {
    return _then(_$OCRItemConfirmationImpl(
      itemId: null == itemId
          ? _value.itemId
          : itemId // ignore: cast_nullable_to_non_nullable
              as String,
      isConfirmed: null == isConfirmed
          ? _value.isConfirmed
          : isConfirmed // ignore: cast_nullable_to_non_nullable
              as bool,
      productId: freezed == productId
          ? _value.productId
          : productId // ignore: cast_nullable_to_non_nullable
              as String?,
      quantity: null == quantity
          ? _value.quantity
          : quantity // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OCRItemConfirmationImpl implements _OCRItemConfirmation {
  const _$OCRItemConfirmationImpl(
      {@JsonKey(name: 'item_id') required this.itemId,
      @JsonKey(name: 'is_confirmed') required this.isConfirmed,
      @JsonKey(name: 'product_id') this.productId,
      required this.quantity});

  factory _$OCRItemConfirmationImpl.fromJson(Map<String, dynamic> json) =>
      _$$OCRItemConfirmationImplFromJson(json);

  @override
  @JsonKey(name: 'item_id')
  final String itemId;
  @override
  @JsonKey(name: 'is_confirmed')
  final bool isConfirmed;
  @override
  @JsonKey(name: 'product_id')
  final String? productId;
  @override
  final int quantity;

  @override
  String toString() {
    return 'OCRItemConfirmation(itemId: $itemId, isConfirmed: $isConfirmed, productId: $productId, quantity: $quantity)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OCRItemConfirmationImpl &&
            (identical(other.itemId, itemId) || other.itemId == itemId) &&
            (identical(other.isConfirmed, isConfirmed) ||
                other.isConfirmed == isConfirmed) &&
            (identical(other.productId, productId) ||
                other.productId == productId) &&
            (identical(other.quantity, quantity) ||
                other.quantity == quantity));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, itemId, isConfirmed, productId, quantity);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$OCRItemConfirmationImplCopyWith<_$OCRItemConfirmationImpl> get copyWith =>
      __$$OCRItemConfirmationImplCopyWithImpl<_$OCRItemConfirmationImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OCRItemConfirmationImplToJson(
      this,
    );
  }
}

abstract class _OCRItemConfirmation implements OCRItemConfirmation {
  const factory _OCRItemConfirmation(
      {@JsonKey(name: 'item_id') required final String itemId,
      @JsonKey(name: 'is_confirmed') required final bool isConfirmed,
      @JsonKey(name: 'product_id') final String? productId,
      required final int quantity}) = _$OCRItemConfirmationImpl;

  factory _OCRItemConfirmation.fromJson(Map<String, dynamic> json) =
      _$OCRItemConfirmationImpl.fromJson;

  @override
  @JsonKey(name: 'item_id')
  String get itemId;
  @override
  @JsonKey(name: 'is_confirmed')
  bool get isConfirmed;
  @override
  @JsonKey(name: 'product_id')
  String? get productId;
  @override
  int get quantity;
  @override
  @JsonKey(ignore: true)
  _$$OCRItemConfirmationImplCopyWith<_$OCRItemConfirmationImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

QuickSaleFromOCRRequest _$QuickSaleFromOCRRequestFromJson(
    Map<String, dynamic> json) {
  return _QuickSaleFromOCRRequest.fromJson(json);
}

/// @nodoc
mixin _$QuickSaleFromOCRRequest {
  @JsonKey(name: 'session_id')
  String get sessionId => throw _privateConstructorUsedError;
  @JsonKey(name: 'customer_phone')
  String? get customerPhone => throw _privateConstructorUsedError;
  @JsonKey(name: 'payment_method')
  String get paymentMethod => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $QuickSaleFromOCRRequestCopyWith<QuickSaleFromOCRRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $QuickSaleFromOCRRequestCopyWith<$Res> {
  factory $QuickSaleFromOCRRequestCopyWith(QuickSaleFromOCRRequest value,
          $Res Function(QuickSaleFromOCRRequest) then) =
      _$QuickSaleFromOCRRequestCopyWithImpl<$Res, QuickSaleFromOCRRequest>;
  @useResult
  $Res call(
      {@JsonKey(name: 'session_id') String sessionId,
      @JsonKey(name: 'customer_phone') String? customerPhone,
      @JsonKey(name: 'payment_method') String paymentMethod,
      String? notes});
}

/// @nodoc
class _$QuickSaleFromOCRRequestCopyWithImpl<$Res,
        $Val extends QuickSaleFromOCRRequest>
    implements $QuickSaleFromOCRRequestCopyWith<$Res> {
  _$QuickSaleFromOCRRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionId = null,
    Object? customerPhone = freezed,
    Object? paymentMethod = null,
    Object? notes = freezed,
  }) {
    return _then(_value.copyWith(
      sessionId: null == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String,
      customerPhone: freezed == customerPhone
          ? _value.customerPhone
          : customerPhone // ignore: cast_nullable_to_non_nullable
              as String?,
      paymentMethod: null == paymentMethod
          ? _value.paymentMethod
          : paymentMethod // ignore: cast_nullable_to_non_nullable
              as String,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$QuickSaleFromOCRRequestImplCopyWith<$Res>
    implements $QuickSaleFromOCRRequestCopyWith<$Res> {
  factory _$$QuickSaleFromOCRRequestImplCopyWith(
          _$QuickSaleFromOCRRequestImpl value,
          $Res Function(_$QuickSaleFromOCRRequestImpl) then) =
      __$$QuickSaleFromOCRRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'session_id') String sessionId,
      @JsonKey(name: 'customer_phone') String? customerPhone,
      @JsonKey(name: 'payment_method') String paymentMethod,
      String? notes});
}

/// @nodoc
class __$$QuickSaleFromOCRRequestImplCopyWithImpl<$Res>
    extends _$QuickSaleFromOCRRequestCopyWithImpl<$Res,
        _$QuickSaleFromOCRRequestImpl>
    implements _$$QuickSaleFromOCRRequestImplCopyWith<$Res> {
  __$$QuickSaleFromOCRRequestImplCopyWithImpl(
      _$QuickSaleFromOCRRequestImpl _value,
      $Res Function(_$QuickSaleFromOCRRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionId = null,
    Object? customerPhone = freezed,
    Object? paymentMethod = null,
    Object? notes = freezed,
  }) {
    return _then(_$QuickSaleFromOCRRequestImpl(
      sessionId: null == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String,
      customerPhone: freezed == customerPhone
          ? _value.customerPhone
          : customerPhone // ignore: cast_nullable_to_non_nullable
              as String?,
      paymentMethod: null == paymentMethod
          ? _value.paymentMethod
          : paymentMethod // ignore: cast_nullable_to_non_nullable
              as String,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$QuickSaleFromOCRRequestImpl implements _QuickSaleFromOCRRequest {
  const _$QuickSaleFromOCRRequestImpl(
      {@JsonKey(name: 'session_id') required this.sessionId,
      @JsonKey(name: 'customer_phone') this.customerPhone,
      @JsonKey(name: 'payment_method') required this.paymentMethod,
      this.notes});

  factory _$QuickSaleFromOCRRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$QuickSaleFromOCRRequestImplFromJson(json);

  @override
  @JsonKey(name: 'session_id')
  final String sessionId;
  @override
  @JsonKey(name: 'customer_phone')
  final String? customerPhone;
  @override
  @JsonKey(name: 'payment_method')
  final String paymentMethod;
  @override
  final String? notes;

  @override
  String toString() {
    return 'QuickSaleFromOCRRequest(sessionId: $sessionId, customerPhone: $customerPhone, paymentMethod: $paymentMethod, notes: $notes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$QuickSaleFromOCRRequestImpl &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.customerPhone, customerPhone) ||
                other.customerPhone == customerPhone) &&
            (identical(other.paymentMethod, paymentMethod) ||
                other.paymentMethod == paymentMethod) &&
            (identical(other.notes, notes) || other.notes == notes));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, sessionId, customerPhone, paymentMethod, notes);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$QuickSaleFromOCRRequestImplCopyWith<_$QuickSaleFromOCRRequestImpl>
      get copyWith => __$$QuickSaleFromOCRRequestImplCopyWithImpl<
          _$QuickSaleFromOCRRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$QuickSaleFromOCRRequestImplToJson(
      this,
    );
  }
}

abstract class _QuickSaleFromOCRRequest implements QuickSaleFromOCRRequest {
  const factory _QuickSaleFromOCRRequest(
      {@JsonKey(name: 'session_id') required final String sessionId,
      @JsonKey(name: 'customer_phone') final String? customerPhone,
      @JsonKey(name: 'payment_method') required final String paymentMethod,
      final String? notes}) = _$QuickSaleFromOCRRequestImpl;

  factory _QuickSaleFromOCRRequest.fromJson(Map<String, dynamic> json) =
      _$QuickSaleFromOCRRequestImpl.fromJson;

  @override
  @JsonKey(name: 'session_id')
  String get sessionId;
  @override
  @JsonKey(name: 'customer_phone')
  String? get customerPhone;
  @override
  @JsonKey(name: 'payment_method')
  String get paymentMethod;
  @override
  String? get notes;
  @override
  @JsonKey(ignore: true)
  _$$QuickSaleFromOCRRequestImplCopyWith<_$QuickSaleFromOCRRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}

OCRMatchingConfig _$OCRMatchingConfigFromJson(Map<String, dynamic> json) {
  return _OCRMatchingConfig.fromJson(json);
}

/// @nodoc
mixin _$OCRMatchingConfig {
  @JsonKey(name: 'min_confidence_score')
  double get minConfidenceScore => throw _privateConstructorUsedError;
  @JsonKey(name: 'fuzzy_match_threshold')
  double get fuzzyMatchThreshold => throw _privateConstructorUsedError;
  @JsonKey(name: 'enable_alias_matching')
  bool get enableAliasMatching => throw _privateConstructorUsedError;
  @JsonKey(name: 'enable_pattern_matching')
  bool get enablePatternMatching => throw _privateConstructorUsedError;
  @JsonKey(name: 'max_suggestions_per_item')
  int get maxSuggestionsPerItem => throw _privateConstructorUsedError;
  @JsonKey(name: 'auto_confirm_high_matches')
  bool get autoConfirmHighMatches => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $OCRMatchingConfigCopyWith<OCRMatchingConfig> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OCRMatchingConfigCopyWith<$Res> {
  factory $OCRMatchingConfigCopyWith(
          OCRMatchingConfig value, $Res Function(OCRMatchingConfig) then) =
      _$OCRMatchingConfigCopyWithImpl<$Res, OCRMatchingConfig>;
  @useResult
  $Res call(
      {@JsonKey(name: 'min_confidence_score') double minConfidenceScore,
      @JsonKey(name: 'fuzzy_match_threshold') double fuzzyMatchThreshold,
      @JsonKey(name: 'enable_alias_matching') bool enableAliasMatching,
      @JsonKey(name: 'enable_pattern_matching') bool enablePatternMatching,
      @JsonKey(name: 'max_suggestions_per_item') int maxSuggestionsPerItem,
      @JsonKey(name: 'auto_confirm_high_matches') bool autoConfirmHighMatches});
}

/// @nodoc
class _$OCRMatchingConfigCopyWithImpl<$Res, $Val extends OCRMatchingConfig>
    implements $OCRMatchingConfigCopyWith<$Res> {
  _$OCRMatchingConfigCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? minConfidenceScore = null,
    Object? fuzzyMatchThreshold = null,
    Object? enableAliasMatching = null,
    Object? enablePatternMatching = null,
    Object? maxSuggestionsPerItem = null,
    Object? autoConfirmHighMatches = null,
  }) {
    return _then(_value.copyWith(
      minConfidenceScore: null == minConfidenceScore
          ? _value.minConfidenceScore
          : minConfidenceScore // ignore: cast_nullable_to_non_nullable
              as double,
      fuzzyMatchThreshold: null == fuzzyMatchThreshold
          ? _value.fuzzyMatchThreshold
          : fuzzyMatchThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      enableAliasMatching: null == enableAliasMatching
          ? _value.enableAliasMatching
          : enableAliasMatching // ignore: cast_nullable_to_non_nullable
              as bool,
      enablePatternMatching: null == enablePatternMatching
          ? _value.enablePatternMatching
          : enablePatternMatching // ignore: cast_nullable_to_non_nullable
              as bool,
      maxSuggestionsPerItem: null == maxSuggestionsPerItem
          ? _value.maxSuggestionsPerItem
          : maxSuggestionsPerItem // ignore: cast_nullable_to_non_nullable
              as int,
      autoConfirmHighMatches: null == autoConfirmHighMatches
          ? _value.autoConfirmHighMatches
          : autoConfirmHighMatches // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OCRMatchingConfigImplCopyWith<$Res>
    implements $OCRMatchingConfigCopyWith<$Res> {
  factory _$$OCRMatchingConfigImplCopyWith(_$OCRMatchingConfigImpl value,
          $Res Function(_$OCRMatchingConfigImpl) then) =
      __$$OCRMatchingConfigImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'min_confidence_score') double minConfidenceScore,
      @JsonKey(name: 'fuzzy_match_threshold') double fuzzyMatchThreshold,
      @JsonKey(name: 'enable_alias_matching') bool enableAliasMatching,
      @JsonKey(name: 'enable_pattern_matching') bool enablePatternMatching,
      @JsonKey(name: 'max_suggestions_per_item') int maxSuggestionsPerItem,
      @JsonKey(name: 'auto_confirm_high_matches') bool autoConfirmHighMatches});
}

/// @nodoc
class __$$OCRMatchingConfigImplCopyWithImpl<$Res>
    extends _$OCRMatchingConfigCopyWithImpl<$Res, _$OCRMatchingConfigImpl>
    implements _$$OCRMatchingConfigImplCopyWith<$Res> {
  __$$OCRMatchingConfigImplCopyWithImpl(_$OCRMatchingConfigImpl _value,
      $Res Function(_$OCRMatchingConfigImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? minConfidenceScore = null,
    Object? fuzzyMatchThreshold = null,
    Object? enableAliasMatching = null,
    Object? enablePatternMatching = null,
    Object? maxSuggestionsPerItem = null,
    Object? autoConfirmHighMatches = null,
  }) {
    return _then(_$OCRMatchingConfigImpl(
      minConfidenceScore: null == minConfidenceScore
          ? _value.minConfidenceScore
          : minConfidenceScore // ignore: cast_nullable_to_non_nullable
              as double,
      fuzzyMatchThreshold: null == fuzzyMatchThreshold
          ? _value.fuzzyMatchThreshold
          : fuzzyMatchThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      enableAliasMatching: null == enableAliasMatching
          ? _value.enableAliasMatching
          : enableAliasMatching // ignore: cast_nullable_to_non_nullable
              as bool,
      enablePatternMatching: null == enablePatternMatching
          ? _value.enablePatternMatching
          : enablePatternMatching // ignore: cast_nullable_to_non_nullable
              as bool,
      maxSuggestionsPerItem: null == maxSuggestionsPerItem
          ? _value.maxSuggestionsPerItem
          : maxSuggestionsPerItem // ignore: cast_nullable_to_non_nullable
              as int,
      autoConfirmHighMatches: null == autoConfirmHighMatches
          ? _value.autoConfirmHighMatches
          : autoConfirmHighMatches // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OCRMatchingConfigImpl implements _OCRMatchingConfig {
  const _$OCRMatchingConfigImpl(
      {@JsonKey(name: 'min_confidence_score') required this.minConfidenceScore,
      @JsonKey(name: 'fuzzy_match_threshold') required this.fuzzyMatchThreshold,
      @JsonKey(name: 'enable_alias_matching') required this.enableAliasMatching,
      @JsonKey(name: 'enable_pattern_matching')
      required this.enablePatternMatching,
      @JsonKey(name: 'max_suggestions_per_item')
      required this.maxSuggestionsPerItem,
      @JsonKey(name: 'auto_confirm_high_matches')
      required this.autoConfirmHighMatches});

  factory _$OCRMatchingConfigImpl.fromJson(Map<String, dynamic> json) =>
      _$$OCRMatchingConfigImplFromJson(json);

  @override
  @JsonKey(name: 'min_confidence_score')
  final double minConfidenceScore;
  @override
  @JsonKey(name: 'fuzzy_match_threshold')
  final double fuzzyMatchThreshold;
  @override
  @JsonKey(name: 'enable_alias_matching')
  final bool enableAliasMatching;
  @override
  @JsonKey(name: 'enable_pattern_matching')
  final bool enablePatternMatching;
  @override
  @JsonKey(name: 'max_suggestions_per_item')
  final int maxSuggestionsPerItem;
  @override
  @JsonKey(name: 'auto_confirm_high_matches')
  final bool autoConfirmHighMatches;

  @override
  String toString() {
    return 'OCRMatchingConfig(minConfidenceScore: $minConfidenceScore, fuzzyMatchThreshold: $fuzzyMatchThreshold, enableAliasMatching: $enableAliasMatching, enablePatternMatching: $enablePatternMatching, maxSuggestionsPerItem: $maxSuggestionsPerItem, autoConfirmHighMatches: $autoConfirmHighMatches)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OCRMatchingConfigImpl &&
            (identical(other.minConfidenceScore, minConfidenceScore) ||
                other.minConfidenceScore == minConfidenceScore) &&
            (identical(other.fuzzyMatchThreshold, fuzzyMatchThreshold) ||
                other.fuzzyMatchThreshold == fuzzyMatchThreshold) &&
            (identical(other.enableAliasMatching, enableAliasMatching) ||
                other.enableAliasMatching == enableAliasMatching) &&
            (identical(other.enablePatternMatching, enablePatternMatching) ||
                other.enablePatternMatching == enablePatternMatching) &&
            (identical(other.maxSuggestionsPerItem, maxSuggestionsPerItem) ||
                other.maxSuggestionsPerItem == maxSuggestionsPerItem) &&
            (identical(other.autoConfirmHighMatches, autoConfirmHighMatches) ||
                other.autoConfirmHighMatches == autoConfirmHighMatches));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      minConfidenceScore,
      fuzzyMatchThreshold,
      enableAliasMatching,
      enablePatternMatching,
      maxSuggestionsPerItem,
      autoConfirmHighMatches);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$OCRMatchingConfigImplCopyWith<_$OCRMatchingConfigImpl> get copyWith =>
      __$$OCRMatchingConfigImplCopyWithImpl<_$OCRMatchingConfigImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OCRMatchingConfigImplToJson(
      this,
    );
  }
}

abstract class _OCRMatchingConfig implements OCRMatchingConfig {
  const factory _OCRMatchingConfig(
      {@JsonKey(name: 'min_confidence_score')
      required final double minConfidenceScore,
      @JsonKey(name: 'fuzzy_match_threshold')
      required final double fuzzyMatchThreshold,
      @JsonKey(name: 'enable_alias_matching')
      required final bool enableAliasMatching,
      @JsonKey(name: 'enable_pattern_matching')
      required final bool enablePatternMatching,
      @JsonKey(name: 'max_suggestions_per_item')
      required final int maxSuggestionsPerItem,
      @JsonKey(name: 'auto_confirm_high_matches')
      required final bool autoConfirmHighMatches}) = _$OCRMatchingConfigImpl;

  factory _OCRMatchingConfig.fromJson(Map<String, dynamic> json) =
      _$OCRMatchingConfigImpl.fromJson;

  @override
  @JsonKey(name: 'min_confidence_score')
  double get minConfidenceScore;
  @override
  @JsonKey(name: 'fuzzy_match_threshold')
  double get fuzzyMatchThreshold;
  @override
  @JsonKey(name: 'enable_alias_matching')
  bool get enableAliasMatching;
  @override
  @JsonKey(name: 'enable_pattern_matching')
  bool get enablePatternMatching;
  @override
  @JsonKey(name: 'max_suggestions_per_item')
  int get maxSuggestionsPerItem;
  @override
  @JsonKey(name: 'auto_confirm_high_matches')
  bool get autoConfirmHighMatches;
  @override
  @JsonKey(ignore: true)
  _$$OCRMatchingConfigImplCopyWith<_$OCRMatchingConfigImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

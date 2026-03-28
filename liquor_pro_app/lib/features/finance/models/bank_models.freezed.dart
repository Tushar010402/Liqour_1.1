// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bank_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TenantBankAccount _$TenantBankAccountFromJson(Map<String, dynamic> json) {
  return _TenantBankAccount.fromJson(json);
}

/// @nodoc
mixin _$TenantBankAccount {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'tenant_id')
  String? get tenantId => throw _privateConstructorUsedError;
  @JsonKey(name: 'bank_name')
  String get bankName => throw _privateConstructorUsedError;
  @JsonKey(name: 'account_number')
  String get accountNumber => throw _privateConstructorUsedError;
  @JsonKey(name: 'account_holder_name')
  String get accountHolderName => throw _privateConstructorUsedError;
  @JsonKey(name: 'ifsc_code')
  String get ifscCode => throw _privateConstructorUsedError;
  @JsonKey(name: 'branch_name')
  String? get branchName => throw _privateConstructorUsedError;
  @JsonKey(name: 'branch_address')
  String? get branchAddress => throw _privateConstructorUsedError;
  @JsonKey(name: 'account_type')
  String get accountType =>
      throw _privateConstructorUsedError; // current, savings, od, cash_credit
  @JsonKey(name: 'current_balance')
  double get currentBalance => throw _privateConstructorUsedError;
  @JsonKey(name: 'od_limit')
  double get odLimit => throw _privateConstructorUsedError;
  @JsonKey(name: 'used_od_amount')
  double get usedOdAmount => throw _privateConstructorUsedError;
  @JsonKey(name: 'available_od')
  double get availableOd =>
      throw _privateConstructorUsedError; // Computed: odLimit - usedOdAmount
  @JsonKey(name: 'total_available_balance')
  double get totalAvailableBalance =>
      throw _privateConstructorUsedError; // Computed: currentBalance + availableOd
  @JsonKey(name: 'od_interest_rate')
  double get odInterestRate => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_active')
  bool get isActive => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_default')
  bool get isDefault => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_by')
  String? get createdBy => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime? get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'updated_at')
  DateTime? get updatedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'deleted_at')
  DateTime? get deletedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $TenantBankAccountCopyWith<TenantBankAccount> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TenantBankAccountCopyWith<$Res> {
  factory $TenantBankAccountCopyWith(
          TenantBankAccount value, $Res Function(TenantBankAccount) then) =
      _$TenantBankAccountCopyWithImpl<$Res, TenantBankAccount>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'tenant_id') String? tenantId,
      @JsonKey(name: 'bank_name') String bankName,
      @JsonKey(name: 'account_number') String accountNumber,
      @JsonKey(name: 'account_holder_name') String accountHolderName,
      @JsonKey(name: 'ifsc_code') String ifscCode,
      @JsonKey(name: 'branch_name') String? branchName,
      @JsonKey(name: 'branch_address') String? branchAddress,
      @JsonKey(name: 'account_type') String accountType,
      @JsonKey(name: 'current_balance') double currentBalance,
      @JsonKey(name: 'od_limit') double odLimit,
      @JsonKey(name: 'used_od_amount') double usedOdAmount,
      @JsonKey(name: 'available_od') double availableOd,
      @JsonKey(name: 'total_available_balance') double totalAvailableBalance,
      @JsonKey(name: 'od_interest_rate') double odInterestRate,
      @JsonKey(name: 'is_active') bool isActive,
      @JsonKey(name: 'is_default') bool isDefault,
      String? notes,
      @JsonKey(name: 'created_by') String? createdBy,
      @JsonKey(name: 'created_at') DateTime? createdAt,
      @JsonKey(name: 'updated_at') DateTime? updatedAt,
      @JsonKey(name: 'deleted_at') DateTime? deletedAt});
}

/// @nodoc
class _$TenantBankAccountCopyWithImpl<$Res, $Val extends TenantBankAccount>
    implements $TenantBankAccountCopyWith<$Res> {
  _$TenantBankAccountCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? tenantId = freezed,
    Object? bankName = null,
    Object? accountNumber = null,
    Object? accountHolderName = null,
    Object? ifscCode = null,
    Object? branchName = freezed,
    Object? branchAddress = freezed,
    Object? accountType = null,
    Object? currentBalance = null,
    Object? odLimit = null,
    Object? usedOdAmount = null,
    Object? availableOd = null,
    Object? totalAvailableBalance = null,
    Object? odInterestRate = null,
    Object? isActive = null,
    Object? isDefault = null,
    Object? notes = freezed,
    Object? createdBy = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? deletedAt = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      tenantId: freezed == tenantId
          ? _value.tenantId
          : tenantId // ignore: cast_nullable_to_non_nullable
              as String?,
      bankName: null == bankName
          ? _value.bankName
          : bankName // ignore: cast_nullable_to_non_nullable
              as String,
      accountNumber: null == accountNumber
          ? _value.accountNumber
          : accountNumber // ignore: cast_nullable_to_non_nullable
              as String,
      accountHolderName: null == accountHolderName
          ? _value.accountHolderName
          : accountHolderName // ignore: cast_nullable_to_non_nullable
              as String,
      ifscCode: null == ifscCode
          ? _value.ifscCode
          : ifscCode // ignore: cast_nullable_to_non_nullable
              as String,
      branchName: freezed == branchName
          ? _value.branchName
          : branchName // ignore: cast_nullable_to_non_nullable
              as String?,
      branchAddress: freezed == branchAddress
          ? _value.branchAddress
          : branchAddress // ignore: cast_nullable_to_non_nullable
              as String?,
      accountType: null == accountType
          ? _value.accountType
          : accountType // ignore: cast_nullable_to_non_nullable
              as String,
      currentBalance: null == currentBalance
          ? _value.currentBalance
          : currentBalance // ignore: cast_nullable_to_non_nullable
              as double,
      odLimit: null == odLimit
          ? _value.odLimit
          : odLimit // ignore: cast_nullable_to_non_nullable
              as double,
      usedOdAmount: null == usedOdAmount
          ? _value.usedOdAmount
          : usedOdAmount // ignore: cast_nullable_to_non_nullable
              as double,
      availableOd: null == availableOd
          ? _value.availableOd
          : availableOd // ignore: cast_nullable_to_non_nullable
              as double,
      totalAvailableBalance: null == totalAvailableBalance
          ? _value.totalAvailableBalance
          : totalAvailableBalance // ignore: cast_nullable_to_non_nullable
              as double,
      odInterestRate: null == odInterestRate
          ? _value.odInterestRate
          : odInterestRate // ignore: cast_nullable_to_non_nullable
              as double,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool,
      isDefault: null == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      createdBy: freezed == createdBy
          ? _value.createdBy
          : createdBy // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      deletedAt: freezed == deletedAt
          ? _value.deletedAt
          : deletedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TenantBankAccountImplCopyWith<$Res>
    implements $TenantBankAccountCopyWith<$Res> {
  factory _$$TenantBankAccountImplCopyWith(_$TenantBankAccountImpl value,
          $Res Function(_$TenantBankAccountImpl) then) =
      __$$TenantBankAccountImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'tenant_id') String? tenantId,
      @JsonKey(name: 'bank_name') String bankName,
      @JsonKey(name: 'account_number') String accountNumber,
      @JsonKey(name: 'account_holder_name') String accountHolderName,
      @JsonKey(name: 'ifsc_code') String ifscCode,
      @JsonKey(name: 'branch_name') String? branchName,
      @JsonKey(name: 'branch_address') String? branchAddress,
      @JsonKey(name: 'account_type') String accountType,
      @JsonKey(name: 'current_balance') double currentBalance,
      @JsonKey(name: 'od_limit') double odLimit,
      @JsonKey(name: 'used_od_amount') double usedOdAmount,
      @JsonKey(name: 'available_od') double availableOd,
      @JsonKey(name: 'total_available_balance') double totalAvailableBalance,
      @JsonKey(name: 'od_interest_rate') double odInterestRate,
      @JsonKey(name: 'is_active') bool isActive,
      @JsonKey(name: 'is_default') bool isDefault,
      String? notes,
      @JsonKey(name: 'created_by') String? createdBy,
      @JsonKey(name: 'created_at') DateTime? createdAt,
      @JsonKey(name: 'updated_at') DateTime? updatedAt,
      @JsonKey(name: 'deleted_at') DateTime? deletedAt});
}

/// @nodoc
class __$$TenantBankAccountImplCopyWithImpl<$Res>
    extends _$TenantBankAccountCopyWithImpl<$Res, _$TenantBankAccountImpl>
    implements _$$TenantBankAccountImplCopyWith<$Res> {
  __$$TenantBankAccountImplCopyWithImpl(_$TenantBankAccountImpl _value,
      $Res Function(_$TenantBankAccountImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? tenantId = freezed,
    Object? bankName = null,
    Object? accountNumber = null,
    Object? accountHolderName = null,
    Object? ifscCode = null,
    Object? branchName = freezed,
    Object? branchAddress = freezed,
    Object? accountType = null,
    Object? currentBalance = null,
    Object? odLimit = null,
    Object? usedOdAmount = null,
    Object? availableOd = null,
    Object? totalAvailableBalance = null,
    Object? odInterestRate = null,
    Object? isActive = null,
    Object? isDefault = null,
    Object? notes = freezed,
    Object? createdBy = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? deletedAt = freezed,
  }) {
    return _then(_$TenantBankAccountImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      tenantId: freezed == tenantId
          ? _value.tenantId
          : tenantId // ignore: cast_nullable_to_non_nullable
              as String?,
      bankName: null == bankName
          ? _value.bankName
          : bankName // ignore: cast_nullable_to_non_nullable
              as String,
      accountNumber: null == accountNumber
          ? _value.accountNumber
          : accountNumber // ignore: cast_nullable_to_non_nullable
              as String,
      accountHolderName: null == accountHolderName
          ? _value.accountHolderName
          : accountHolderName // ignore: cast_nullable_to_non_nullable
              as String,
      ifscCode: null == ifscCode
          ? _value.ifscCode
          : ifscCode // ignore: cast_nullable_to_non_nullable
              as String,
      branchName: freezed == branchName
          ? _value.branchName
          : branchName // ignore: cast_nullable_to_non_nullable
              as String?,
      branchAddress: freezed == branchAddress
          ? _value.branchAddress
          : branchAddress // ignore: cast_nullable_to_non_nullable
              as String?,
      accountType: null == accountType
          ? _value.accountType
          : accountType // ignore: cast_nullable_to_non_nullable
              as String,
      currentBalance: null == currentBalance
          ? _value.currentBalance
          : currentBalance // ignore: cast_nullable_to_non_nullable
              as double,
      odLimit: null == odLimit
          ? _value.odLimit
          : odLimit // ignore: cast_nullable_to_non_nullable
              as double,
      usedOdAmount: null == usedOdAmount
          ? _value.usedOdAmount
          : usedOdAmount // ignore: cast_nullable_to_non_nullable
              as double,
      availableOd: null == availableOd
          ? _value.availableOd
          : availableOd // ignore: cast_nullable_to_non_nullable
              as double,
      totalAvailableBalance: null == totalAvailableBalance
          ? _value.totalAvailableBalance
          : totalAvailableBalance // ignore: cast_nullable_to_non_nullable
              as double,
      odInterestRate: null == odInterestRate
          ? _value.odInterestRate
          : odInterestRate // ignore: cast_nullable_to_non_nullable
              as double,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool,
      isDefault: null == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      createdBy: freezed == createdBy
          ? _value.createdBy
          : createdBy // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      deletedAt: freezed == deletedAt
          ? _value.deletedAt
          : deletedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TenantBankAccountImpl implements _TenantBankAccount {
  const _$TenantBankAccountImpl(
      {required this.id,
      @JsonKey(name: 'tenant_id') this.tenantId,
      @JsonKey(name: 'bank_name') this.bankName = '',
      @JsonKey(name: 'account_number') this.accountNumber = '',
      @JsonKey(name: 'account_holder_name') this.accountHolderName = '',
      @JsonKey(name: 'ifsc_code') this.ifscCode = '',
      @JsonKey(name: 'branch_name') this.branchName,
      @JsonKey(name: 'branch_address') this.branchAddress,
      @JsonKey(name: 'account_type') this.accountType = 'savings',
      @JsonKey(name: 'current_balance') this.currentBalance = 0.0,
      @JsonKey(name: 'od_limit') this.odLimit = 0.0,
      @JsonKey(name: 'used_od_amount') this.usedOdAmount = 0.0,
      @JsonKey(name: 'available_od') this.availableOd = 0.0,
      @JsonKey(name: 'total_available_balance')
      this.totalAvailableBalance = 0.0,
      @JsonKey(name: 'od_interest_rate') this.odInterestRate = 0.0,
      @JsonKey(name: 'is_active') this.isActive = true,
      @JsonKey(name: 'is_default') this.isDefault = false,
      this.notes,
      @JsonKey(name: 'created_by') this.createdBy,
      @JsonKey(name: 'created_at') this.createdAt,
      @JsonKey(name: 'updated_at') this.updatedAt,
      @JsonKey(name: 'deleted_at') this.deletedAt});

  factory _$TenantBankAccountImpl.fromJson(Map<String, dynamic> json) =>
      _$$TenantBankAccountImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'tenant_id')
  final String? tenantId;
  @override
  @JsonKey(name: 'bank_name')
  final String bankName;
  @override
  @JsonKey(name: 'account_number')
  final String accountNumber;
  @override
  @JsonKey(name: 'account_holder_name')
  final String accountHolderName;
  @override
  @JsonKey(name: 'ifsc_code')
  final String ifscCode;
  @override
  @JsonKey(name: 'branch_name')
  final String? branchName;
  @override
  @JsonKey(name: 'branch_address')
  final String? branchAddress;
  @override
  @JsonKey(name: 'account_type')
  final String accountType;
// current, savings, od, cash_credit
  @override
  @JsonKey(name: 'current_balance')
  final double currentBalance;
  @override
  @JsonKey(name: 'od_limit')
  final double odLimit;
  @override
  @JsonKey(name: 'used_od_amount')
  final double usedOdAmount;
  @override
  @JsonKey(name: 'available_od')
  final double availableOd;
// Computed: odLimit - usedOdAmount
  @override
  @JsonKey(name: 'total_available_balance')
  final double totalAvailableBalance;
// Computed: currentBalance + availableOd
  @override
  @JsonKey(name: 'od_interest_rate')
  final double odInterestRate;
  @override
  @JsonKey(name: 'is_active')
  final bool isActive;
  @override
  @JsonKey(name: 'is_default')
  final bool isDefault;
  @override
  final String? notes;
  @override
  @JsonKey(name: 'created_by')
  final String? createdBy;
  @override
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  @override
  @JsonKey(name: 'updated_at')
  final DateTime? updatedAt;
  @override
  @JsonKey(name: 'deleted_at')
  final DateTime? deletedAt;

  @override
  String toString() {
    return 'TenantBankAccount(id: $id, tenantId: $tenantId, bankName: $bankName, accountNumber: $accountNumber, accountHolderName: $accountHolderName, ifscCode: $ifscCode, branchName: $branchName, branchAddress: $branchAddress, accountType: $accountType, currentBalance: $currentBalance, odLimit: $odLimit, usedOdAmount: $usedOdAmount, availableOd: $availableOd, totalAvailableBalance: $totalAvailableBalance, odInterestRate: $odInterestRate, isActive: $isActive, isDefault: $isDefault, notes: $notes, createdBy: $createdBy, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TenantBankAccountImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.tenantId, tenantId) ||
                other.tenantId == tenantId) &&
            (identical(other.bankName, bankName) ||
                other.bankName == bankName) &&
            (identical(other.accountNumber, accountNumber) ||
                other.accountNumber == accountNumber) &&
            (identical(other.accountHolderName, accountHolderName) ||
                other.accountHolderName == accountHolderName) &&
            (identical(other.ifscCode, ifscCode) ||
                other.ifscCode == ifscCode) &&
            (identical(other.branchName, branchName) ||
                other.branchName == branchName) &&
            (identical(other.branchAddress, branchAddress) ||
                other.branchAddress == branchAddress) &&
            (identical(other.accountType, accountType) ||
                other.accountType == accountType) &&
            (identical(other.currentBalance, currentBalance) ||
                other.currentBalance == currentBalance) &&
            (identical(other.odLimit, odLimit) || other.odLimit == odLimit) &&
            (identical(other.usedOdAmount, usedOdAmount) ||
                other.usedOdAmount == usedOdAmount) &&
            (identical(other.availableOd, availableOd) ||
                other.availableOd == availableOd) &&
            (identical(other.totalAvailableBalance, totalAvailableBalance) ||
                other.totalAvailableBalance == totalAvailableBalance) &&
            (identical(other.odInterestRate, odInterestRate) ||
                other.odInterestRate == odInterestRate) &&
            (identical(other.isActive, isActive) ||
                other.isActive == isActive) &&
            (identical(other.isDefault, isDefault) ||
                other.isDefault == isDefault) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.createdBy, createdBy) ||
                other.createdBy == createdBy) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.deletedAt, deletedAt) ||
                other.deletedAt == deletedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        tenantId,
        bankName,
        accountNumber,
        accountHolderName,
        ifscCode,
        branchName,
        branchAddress,
        accountType,
        currentBalance,
        odLimit,
        usedOdAmount,
        availableOd,
        totalAvailableBalance,
        odInterestRate,
        isActive,
        isDefault,
        notes,
        createdBy,
        createdAt,
        updatedAt,
        deletedAt
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TenantBankAccountImplCopyWith<_$TenantBankAccountImpl> get copyWith =>
      __$$TenantBankAccountImplCopyWithImpl<_$TenantBankAccountImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TenantBankAccountImplToJson(
      this,
    );
  }
}

abstract class _TenantBankAccount implements TenantBankAccount {
  const factory _TenantBankAccount(
          {required final String id,
          @JsonKey(name: 'tenant_id') final String? tenantId,
          @JsonKey(name: 'bank_name') final String bankName,
          @JsonKey(name: 'account_number') final String accountNumber,
          @JsonKey(name: 'account_holder_name') final String accountHolderName,
          @JsonKey(name: 'ifsc_code') final String ifscCode,
          @JsonKey(name: 'branch_name') final String? branchName,
          @JsonKey(name: 'branch_address') final String? branchAddress,
          @JsonKey(name: 'account_type') final String accountType,
          @JsonKey(name: 'current_balance') final double currentBalance,
          @JsonKey(name: 'od_limit') final double odLimit,
          @JsonKey(name: 'used_od_amount') final double usedOdAmount,
          @JsonKey(name: 'available_od') final double availableOd,
          @JsonKey(name: 'total_available_balance')
          final double totalAvailableBalance,
          @JsonKey(name: 'od_interest_rate') final double odInterestRate,
          @JsonKey(name: 'is_active') final bool isActive,
          @JsonKey(name: 'is_default') final bool isDefault,
          final String? notes,
          @JsonKey(name: 'created_by') final String? createdBy,
          @JsonKey(name: 'created_at') final DateTime? createdAt,
          @JsonKey(name: 'updated_at') final DateTime? updatedAt,
          @JsonKey(name: 'deleted_at') final DateTime? deletedAt}) =
      _$TenantBankAccountImpl;

  factory _TenantBankAccount.fromJson(Map<String, dynamic> json) =
      _$TenantBankAccountImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'tenant_id')
  String? get tenantId;
  @override
  @JsonKey(name: 'bank_name')
  String get bankName;
  @override
  @JsonKey(name: 'account_number')
  String get accountNumber;
  @override
  @JsonKey(name: 'account_holder_name')
  String get accountHolderName;
  @override
  @JsonKey(name: 'ifsc_code')
  String get ifscCode;
  @override
  @JsonKey(name: 'branch_name')
  String? get branchName;
  @override
  @JsonKey(name: 'branch_address')
  String? get branchAddress;
  @override
  @JsonKey(name: 'account_type')
  String get accountType;
  @override // current, savings, od, cash_credit
  @JsonKey(name: 'current_balance')
  double get currentBalance;
  @override
  @JsonKey(name: 'od_limit')
  double get odLimit;
  @override
  @JsonKey(name: 'used_od_amount')
  double get usedOdAmount;
  @override
  @JsonKey(name: 'available_od')
  double get availableOd;
  @override // Computed: odLimit - usedOdAmount
  @JsonKey(name: 'total_available_balance')
  double get totalAvailableBalance;
  @override // Computed: currentBalance + availableOd
  @JsonKey(name: 'od_interest_rate')
  double get odInterestRate;
  @override
  @JsonKey(name: 'is_active')
  bool get isActive;
  @override
  @JsonKey(name: 'is_default')
  bool get isDefault;
  @override
  String? get notes;
  @override
  @JsonKey(name: 'created_by')
  String? get createdBy;
  @override
  @JsonKey(name: 'created_at')
  DateTime? get createdAt;
  @override
  @JsonKey(name: 'updated_at')
  DateTime? get updatedAt;
  @override
  @JsonKey(name: 'deleted_at')
  DateTime? get deletedAt;
  @override
  @JsonKey(ignore: true)
  _$$TenantBankAccountImplCopyWith<_$TenantBankAccountImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

BankTransaction _$BankTransactionFromJson(Map<String, dynamic> json) {
  return _BankTransaction.fromJson(json);
}

/// @nodoc
mixin _$BankTransaction {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'bank_account_id')
  String get bankAccountId => throw _privateConstructorUsedError;
  @JsonKey(name: 'tenant_id')
  String? get tenantId => throw _privateConstructorUsedError;
  @JsonKey(name: 'transaction_type')
  String get transactionType =>
      throw _privateConstructorUsedError; // deposit, withdrawal, od_usage, od_repayment, interest_charge, bank_charges, adjustment
  double get amount => throw _privateConstructorUsedError;
  @JsonKey(name: 'balance_before')
  double get balanceBefore => throw _privateConstructorUsedError;
  @JsonKey(name: 'balance_after')
  double get balanceAfter => throw _privateConstructorUsedError;
  @JsonKey(name: 'od_used_before')
  double get odUsedBefore => throw _privateConstructorUsedError;
  @JsonKey(name: 'od_used_after')
  double get odUsedAfter => throw _privateConstructorUsedError;
  @JsonKey(name: 'reference_type')
  String? get referenceType =>
      throw _privateConstructorUsedError; // cash_submission, manual, vendor_payment, etc.
  @JsonKey(name: 'reference_id')
  String? get referenceId => throw _privateConstructorUsedError;
  @JsonKey(name: 'bank_reference_no')
  String? get bankReferenceNo => throw _privateConstructorUsedError;
  @JsonKey(name: 'transaction_date')
  DateTime? get transactionDate => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_reconciled')
  bool get isReconciled => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_by')
  String? get createdBy => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime? get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'updated_at')
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BankTransactionCopyWith<BankTransaction> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BankTransactionCopyWith<$Res> {
  factory $BankTransactionCopyWith(
          BankTransaction value, $Res Function(BankTransaction) then) =
      _$BankTransactionCopyWithImpl<$Res, BankTransaction>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'bank_account_id') String bankAccountId,
      @JsonKey(name: 'tenant_id') String? tenantId,
      @JsonKey(name: 'transaction_type') String transactionType,
      double amount,
      @JsonKey(name: 'balance_before') double balanceBefore,
      @JsonKey(name: 'balance_after') double balanceAfter,
      @JsonKey(name: 'od_used_before') double odUsedBefore,
      @JsonKey(name: 'od_used_after') double odUsedAfter,
      @JsonKey(name: 'reference_type') String? referenceType,
      @JsonKey(name: 'reference_id') String? referenceId,
      @JsonKey(name: 'bank_reference_no') String? bankReferenceNo,
      @JsonKey(name: 'transaction_date') DateTime? transactionDate,
      String? description,
      String? notes,
      @JsonKey(name: 'is_reconciled') bool isReconciled,
      @JsonKey(name: 'created_by') String? createdBy,
      @JsonKey(name: 'created_at') DateTime? createdAt,
      @JsonKey(name: 'updated_at') DateTime? updatedAt});
}

/// @nodoc
class _$BankTransactionCopyWithImpl<$Res, $Val extends BankTransaction>
    implements $BankTransactionCopyWith<$Res> {
  _$BankTransactionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? bankAccountId = null,
    Object? tenantId = freezed,
    Object? transactionType = null,
    Object? amount = null,
    Object? balanceBefore = null,
    Object? balanceAfter = null,
    Object? odUsedBefore = null,
    Object? odUsedAfter = null,
    Object? referenceType = freezed,
    Object? referenceId = freezed,
    Object? bankReferenceNo = freezed,
    Object? transactionDate = freezed,
    Object? description = freezed,
    Object? notes = freezed,
    Object? isReconciled = null,
    Object? createdBy = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      bankAccountId: null == bankAccountId
          ? _value.bankAccountId
          : bankAccountId // ignore: cast_nullable_to_non_nullable
              as String,
      tenantId: freezed == tenantId
          ? _value.tenantId
          : tenantId // ignore: cast_nullable_to_non_nullable
              as String?,
      transactionType: null == transactionType
          ? _value.transactionType
          : transactionType // ignore: cast_nullable_to_non_nullable
              as String,
      amount: null == amount
          ? _value.amount
          : amount // ignore: cast_nullable_to_non_nullable
              as double,
      balanceBefore: null == balanceBefore
          ? _value.balanceBefore
          : balanceBefore // ignore: cast_nullable_to_non_nullable
              as double,
      balanceAfter: null == balanceAfter
          ? _value.balanceAfter
          : balanceAfter // ignore: cast_nullable_to_non_nullable
              as double,
      odUsedBefore: null == odUsedBefore
          ? _value.odUsedBefore
          : odUsedBefore // ignore: cast_nullable_to_non_nullable
              as double,
      odUsedAfter: null == odUsedAfter
          ? _value.odUsedAfter
          : odUsedAfter // ignore: cast_nullable_to_non_nullable
              as double,
      referenceType: freezed == referenceType
          ? _value.referenceType
          : referenceType // ignore: cast_nullable_to_non_nullable
              as String?,
      referenceId: freezed == referenceId
          ? _value.referenceId
          : referenceId // ignore: cast_nullable_to_non_nullable
              as String?,
      bankReferenceNo: freezed == bankReferenceNo
          ? _value.bankReferenceNo
          : bankReferenceNo // ignore: cast_nullable_to_non_nullable
              as String?,
      transactionDate: freezed == transactionDate
          ? _value.transactionDate
          : transactionDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      isReconciled: null == isReconciled
          ? _value.isReconciled
          : isReconciled // ignore: cast_nullable_to_non_nullable
              as bool,
      createdBy: freezed == createdBy
          ? _value.createdBy
          : createdBy // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BankTransactionImplCopyWith<$Res>
    implements $BankTransactionCopyWith<$Res> {
  factory _$$BankTransactionImplCopyWith(_$BankTransactionImpl value,
          $Res Function(_$BankTransactionImpl) then) =
      __$$BankTransactionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'bank_account_id') String bankAccountId,
      @JsonKey(name: 'tenant_id') String? tenantId,
      @JsonKey(name: 'transaction_type') String transactionType,
      double amount,
      @JsonKey(name: 'balance_before') double balanceBefore,
      @JsonKey(name: 'balance_after') double balanceAfter,
      @JsonKey(name: 'od_used_before') double odUsedBefore,
      @JsonKey(name: 'od_used_after') double odUsedAfter,
      @JsonKey(name: 'reference_type') String? referenceType,
      @JsonKey(name: 'reference_id') String? referenceId,
      @JsonKey(name: 'bank_reference_no') String? bankReferenceNo,
      @JsonKey(name: 'transaction_date') DateTime? transactionDate,
      String? description,
      String? notes,
      @JsonKey(name: 'is_reconciled') bool isReconciled,
      @JsonKey(name: 'created_by') String? createdBy,
      @JsonKey(name: 'created_at') DateTime? createdAt,
      @JsonKey(name: 'updated_at') DateTime? updatedAt});
}

/// @nodoc
class __$$BankTransactionImplCopyWithImpl<$Res>
    extends _$BankTransactionCopyWithImpl<$Res, _$BankTransactionImpl>
    implements _$$BankTransactionImplCopyWith<$Res> {
  __$$BankTransactionImplCopyWithImpl(
      _$BankTransactionImpl _value, $Res Function(_$BankTransactionImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? bankAccountId = null,
    Object? tenantId = freezed,
    Object? transactionType = null,
    Object? amount = null,
    Object? balanceBefore = null,
    Object? balanceAfter = null,
    Object? odUsedBefore = null,
    Object? odUsedAfter = null,
    Object? referenceType = freezed,
    Object? referenceId = freezed,
    Object? bankReferenceNo = freezed,
    Object? transactionDate = freezed,
    Object? description = freezed,
    Object? notes = freezed,
    Object? isReconciled = null,
    Object? createdBy = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_$BankTransactionImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      bankAccountId: null == bankAccountId
          ? _value.bankAccountId
          : bankAccountId // ignore: cast_nullable_to_non_nullable
              as String,
      tenantId: freezed == tenantId
          ? _value.tenantId
          : tenantId // ignore: cast_nullable_to_non_nullable
              as String?,
      transactionType: null == transactionType
          ? _value.transactionType
          : transactionType // ignore: cast_nullable_to_non_nullable
              as String,
      amount: null == amount
          ? _value.amount
          : amount // ignore: cast_nullable_to_non_nullable
              as double,
      balanceBefore: null == balanceBefore
          ? _value.balanceBefore
          : balanceBefore // ignore: cast_nullable_to_non_nullable
              as double,
      balanceAfter: null == balanceAfter
          ? _value.balanceAfter
          : balanceAfter // ignore: cast_nullable_to_non_nullable
              as double,
      odUsedBefore: null == odUsedBefore
          ? _value.odUsedBefore
          : odUsedBefore // ignore: cast_nullable_to_non_nullable
              as double,
      odUsedAfter: null == odUsedAfter
          ? _value.odUsedAfter
          : odUsedAfter // ignore: cast_nullable_to_non_nullable
              as double,
      referenceType: freezed == referenceType
          ? _value.referenceType
          : referenceType // ignore: cast_nullable_to_non_nullable
              as String?,
      referenceId: freezed == referenceId
          ? _value.referenceId
          : referenceId // ignore: cast_nullable_to_non_nullable
              as String?,
      bankReferenceNo: freezed == bankReferenceNo
          ? _value.bankReferenceNo
          : bankReferenceNo // ignore: cast_nullable_to_non_nullable
              as String?,
      transactionDate: freezed == transactionDate
          ? _value.transactionDate
          : transactionDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      isReconciled: null == isReconciled
          ? _value.isReconciled
          : isReconciled // ignore: cast_nullable_to_non_nullable
              as bool,
      createdBy: freezed == createdBy
          ? _value.createdBy
          : createdBy // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BankTransactionImpl implements _BankTransaction {
  const _$BankTransactionImpl(
      {required this.id,
      @JsonKey(name: 'bank_account_id') this.bankAccountId = '',
      @JsonKey(name: 'tenant_id') this.tenantId,
      @JsonKey(name: 'transaction_type') this.transactionType = 'adjustment',
      this.amount = 0.0,
      @JsonKey(name: 'balance_before') this.balanceBefore = 0.0,
      @JsonKey(name: 'balance_after') this.balanceAfter = 0.0,
      @JsonKey(name: 'od_used_before') this.odUsedBefore = 0.0,
      @JsonKey(name: 'od_used_after') this.odUsedAfter = 0.0,
      @JsonKey(name: 'reference_type') this.referenceType,
      @JsonKey(name: 'reference_id') this.referenceId,
      @JsonKey(name: 'bank_reference_no') this.bankReferenceNo,
      @JsonKey(name: 'transaction_date') this.transactionDate,
      this.description,
      this.notes,
      @JsonKey(name: 'is_reconciled') this.isReconciled = false,
      @JsonKey(name: 'created_by') this.createdBy,
      @JsonKey(name: 'created_at') this.createdAt,
      @JsonKey(name: 'updated_at') this.updatedAt});

  factory _$BankTransactionImpl.fromJson(Map<String, dynamic> json) =>
      _$$BankTransactionImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'bank_account_id')
  final String bankAccountId;
  @override
  @JsonKey(name: 'tenant_id')
  final String? tenantId;
  @override
  @JsonKey(name: 'transaction_type')
  final String transactionType;
// deposit, withdrawal, od_usage, od_repayment, interest_charge, bank_charges, adjustment
  @override
  @JsonKey()
  final double amount;
  @override
  @JsonKey(name: 'balance_before')
  final double balanceBefore;
  @override
  @JsonKey(name: 'balance_after')
  final double balanceAfter;
  @override
  @JsonKey(name: 'od_used_before')
  final double odUsedBefore;
  @override
  @JsonKey(name: 'od_used_after')
  final double odUsedAfter;
  @override
  @JsonKey(name: 'reference_type')
  final String? referenceType;
// cash_submission, manual, vendor_payment, etc.
  @override
  @JsonKey(name: 'reference_id')
  final String? referenceId;
  @override
  @JsonKey(name: 'bank_reference_no')
  final String? bankReferenceNo;
  @override
  @JsonKey(name: 'transaction_date')
  final DateTime? transactionDate;
  @override
  final String? description;
  @override
  final String? notes;
  @override
  @JsonKey(name: 'is_reconciled')
  final bool isReconciled;
  @override
  @JsonKey(name: 'created_by')
  final String? createdBy;
  @override
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  @override
  @JsonKey(name: 'updated_at')
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'BankTransaction(id: $id, bankAccountId: $bankAccountId, tenantId: $tenantId, transactionType: $transactionType, amount: $amount, balanceBefore: $balanceBefore, balanceAfter: $balanceAfter, odUsedBefore: $odUsedBefore, odUsedAfter: $odUsedAfter, referenceType: $referenceType, referenceId: $referenceId, bankReferenceNo: $bankReferenceNo, transactionDate: $transactionDate, description: $description, notes: $notes, isReconciled: $isReconciled, createdBy: $createdBy, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BankTransactionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.bankAccountId, bankAccountId) ||
                other.bankAccountId == bankAccountId) &&
            (identical(other.tenantId, tenantId) ||
                other.tenantId == tenantId) &&
            (identical(other.transactionType, transactionType) ||
                other.transactionType == transactionType) &&
            (identical(other.amount, amount) || other.amount == amount) &&
            (identical(other.balanceBefore, balanceBefore) ||
                other.balanceBefore == balanceBefore) &&
            (identical(other.balanceAfter, balanceAfter) ||
                other.balanceAfter == balanceAfter) &&
            (identical(other.odUsedBefore, odUsedBefore) ||
                other.odUsedBefore == odUsedBefore) &&
            (identical(other.odUsedAfter, odUsedAfter) ||
                other.odUsedAfter == odUsedAfter) &&
            (identical(other.referenceType, referenceType) ||
                other.referenceType == referenceType) &&
            (identical(other.referenceId, referenceId) ||
                other.referenceId == referenceId) &&
            (identical(other.bankReferenceNo, bankReferenceNo) ||
                other.bankReferenceNo == bankReferenceNo) &&
            (identical(other.transactionDate, transactionDate) ||
                other.transactionDate == transactionDate) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.isReconciled, isReconciled) ||
                other.isReconciled == isReconciled) &&
            (identical(other.createdBy, createdBy) ||
                other.createdBy == createdBy) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        bankAccountId,
        tenantId,
        transactionType,
        amount,
        balanceBefore,
        balanceAfter,
        odUsedBefore,
        odUsedAfter,
        referenceType,
        referenceId,
        bankReferenceNo,
        transactionDate,
        description,
        notes,
        isReconciled,
        createdBy,
        createdAt,
        updatedAt
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BankTransactionImplCopyWith<_$BankTransactionImpl> get copyWith =>
      __$$BankTransactionImplCopyWithImpl<_$BankTransactionImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BankTransactionImplToJson(
      this,
    );
  }
}

abstract class _BankTransaction implements BankTransaction {
  const factory _BankTransaction(
          {required final String id,
          @JsonKey(name: 'bank_account_id') final String bankAccountId,
          @JsonKey(name: 'tenant_id') final String? tenantId,
          @JsonKey(name: 'transaction_type') final String transactionType,
          final double amount,
          @JsonKey(name: 'balance_before') final double balanceBefore,
          @JsonKey(name: 'balance_after') final double balanceAfter,
          @JsonKey(name: 'od_used_before') final double odUsedBefore,
          @JsonKey(name: 'od_used_after') final double odUsedAfter,
          @JsonKey(name: 'reference_type') final String? referenceType,
          @JsonKey(name: 'reference_id') final String? referenceId,
          @JsonKey(name: 'bank_reference_no') final String? bankReferenceNo,
          @JsonKey(name: 'transaction_date') final DateTime? transactionDate,
          final String? description,
          final String? notes,
          @JsonKey(name: 'is_reconciled') final bool isReconciled,
          @JsonKey(name: 'created_by') final String? createdBy,
          @JsonKey(name: 'created_at') final DateTime? createdAt,
          @JsonKey(name: 'updated_at') final DateTime? updatedAt}) =
      _$BankTransactionImpl;

  factory _BankTransaction.fromJson(Map<String, dynamic> json) =
      _$BankTransactionImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'bank_account_id')
  String get bankAccountId;
  @override
  @JsonKey(name: 'tenant_id')
  String? get tenantId;
  @override
  @JsonKey(name: 'transaction_type')
  String get transactionType;
  @override // deposit, withdrawal, od_usage, od_repayment, interest_charge, bank_charges, adjustment
  double get amount;
  @override
  @JsonKey(name: 'balance_before')
  double get balanceBefore;
  @override
  @JsonKey(name: 'balance_after')
  double get balanceAfter;
  @override
  @JsonKey(name: 'od_used_before')
  double get odUsedBefore;
  @override
  @JsonKey(name: 'od_used_after')
  double get odUsedAfter;
  @override
  @JsonKey(name: 'reference_type')
  String? get referenceType;
  @override // cash_submission, manual, vendor_payment, etc.
  @JsonKey(name: 'reference_id')
  String? get referenceId;
  @override
  @JsonKey(name: 'bank_reference_no')
  String? get bankReferenceNo;
  @override
  @JsonKey(name: 'transaction_date')
  DateTime? get transactionDate;
  @override
  String? get description;
  @override
  String? get notes;
  @override
  @JsonKey(name: 'is_reconciled')
  bool get isReconciled;
  @override
  @JsonKey(name: 'created_by')
  String? get createdBy;
  @override
  @JsonKey(name: 'created_at')
  DateTime? get createdAt;
  @override
  @JsonKey(name: 'updated_at')
  DateTime? get updatedAt;
  @override
  @JsonKey(ignore: true)
  _$$BankTransactionImplCopyWith<_$BankTransactionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

BankReconciliation _$BankReconciliationFromJson(Map<String, dynamic> json) {
  return _BankReconciliation.fromJson(json);
}

/// @nodoc
mixin _$BankReconciliation {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'bank_account_id')
  String get bankAccountId => throw _privateConstructorUsedError;
  @JsonKey(name: 'tenant_id')
  String? get tenantId => throw _privateConstructorUsedError;
  @JsonKey(name: 'reconciliation_date')
  DateTime? get reconciliationDate => throw _privateConstructorUsedError;
  @JsonKey(name: 'system_balance')
  double get systemBalance => throw _privateConstructorUsedError;
  @JsonKey(name: 'bank_statement_balance')
  double get bankStatementBalance => throw _privateConstructorUsedError;
  double get difference =>
      throw _privateConstructorUsedError; // Computed: systemBalance - bankStatementBalance
  String get status =>
      throw _privateConstructorUsedError; // pending, completed, discrepancy
  @JsonKey(name: 'total_deposits')
  double get totalDeposits => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_withdrawals')
  double get totalWithdrawals => throw _privateConstructorUsedError;
  @JsonKey(name: 'transaction_count')
  int get transactionCount => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;
  @JsonKey(name: 'reconciled_by')
  String get reconciledBy => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime? get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'updated_at')
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BankReconciliationCopyWith<BankReconciliation> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BankReconciliationCopyWith<$Res> {
  factory $BankReconciliationCopyWith(
          BankReconciliation value, $Res Function(BankReconciliation) then) =
      _$BankReconciliationCopyWithImpl<$Res, BankReconciliation>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'bank_account_id') String bankAccountId,
      @JsonKey(name: 'tenant_id') String? tenantId,
      @JsonKey(name: 'reconciliation_date') DateTime? reconciliationDate,
      @JsonKey(name: 'system_balance') double systemBalance,
      @JsonKey(name: 'bank_statement_balance') double bankStatementBalance,
      double difference,
      String status,
      @JsonKey(name: 'total_deposits') double totalDeposits,
      @JsonKey(name: 'total_withdrawals') double totalWithdrawals,
      @JsonKey(name: 'transaction_count') int transactionCount,
      String? notes,
      @JsonKey(name: 'reconciled_by') String reconciledBy,
      @JsonKey(name: 'created_at') DateTime? createdAt,
      @JsonKey(name: 'updated_at') DateTime? updatedAt});
}

/// @nodoc
class _$BankReconciliationCopyWithImpl<$Res, $Val extends BankReconciliation>
    implements $BankReconciliationCopyWith<$Res> {
  _$BankReconciliationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? bankAccountId = null,
    Object? tenantId = freezed,
    Object? reconciliationDate = freezed,
    Object? systemBalance = null,
    Object? bankStatementBalance = null,
    Object? difference = null,
    Object? status = null,
    Object? totalDeposits = null,
    Object? totalWithdrawals = null,
    Object? transactionCount = null,
    Object? notes = freezed,
    Object? reconciledBy = null,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      bankAccountId: null == bankAccountId
          ? _value.bankAccountId
          : bankAccountId // ignore: cast_nullable_to_non_nullable
              as String,
      tenantId: freezed == tenantId
          ? _value.tenantId
          : tenantId // ignore: cast_nullable_to_non_nullable
              as String?,
      reconciliationDate: freezed == reconciliationDate
          ? _value.reconciliationDate
          : reconciliationDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      systemBalance: null == systemBalance
          ? _value.systemBalance
          : systemBalance // ignore: cast_nullable_to_non_nullable
              as double,
      bankStatementBalance: null == bankStatementBalance
          ? _value.bankStatementBalance
          : bankStatementBalance // ignore: cast_nullable_to_non_nullable
              as double,
      difference: null == difference
          ? _value.difference
          : difference // ignore: cast_nullable_to_non_nullable
              as double,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      totalDeposits: null == totalDeposits
          ? _value.totalDeposits
          : totalDeposits // ignore: cast_nullable_to_non_nullable
              as double,
      totalWithdrawals: null == totalWithdrawals
          ? _value.totalWithdrawals
          : totalWithdrawals // ignore: cast_nullable_to_non_nullable
              as double,
      transactionCount: null == transactionCount
          ? _value.transactionCount
          : transactionCount // ignore: cast_nullable_to_non_nullable
              as int,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      reconciledBy: null == reconciledBy
          ? _value.reconciledBy
          : reconciledBy // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BankReconciliationImplCopyWith<$Res>
    implements $BankReconciliationCopyWith<$Res> {
  factory _$$BankReconciliationImplCopyWith(_$BankReconciliationImpl value,
          $Res Function(_$BankReconciliationImpl) then) =
      __$$BankReconciliationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'bank_account_id') String bankAccountId,
      @JsonKey(name: 'tenant_id') String? tenantId,
      @JsonKey(name: 'reconciliation_date') DateTime? reconciliationDate,
      @JsonKey(name: 'system_balance') double systemBalance,
      @JsonKey(name: 'bank_statement_balance') double bankStatementBalance,
      double difference,
      String status,
      @JsonKey(name: 'total_deposits') double totalDeposits,
      @JsonKey(name: 'total_withdrawals') double totalWithdrawals,
      @JsonKey(name: 'transaction_count') int transactionCount,
      String? notes,
      @JsonKey(name: 'reconciled_by') String reconciledBy,
      @JsonKey(name: 'created_at') DateTime? createdAt,
      @JsonKey(name: 'updated_at') DateTime? updatedAt});
}

/// @nodoc
class __$$BankReconciliationImplCopyWithImpl<$Res>
    extends _$BankReconciliationCopyWithImpl<$Res, _$BankReconciliationImpl>
    implements _$$BankReconciliationImplCopyWith<$Res> {
  __$$BankReconciliationImplCopyWithImpl(_$BankReconciliationImpl _value,
      $Res Function(_$BankReconciliationImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? bankAccountId = null,
    Object? tenantId = freezed,
    Object? reconciliationDate = freezed,
    Object? systemBalance = null,
    Object? bankStatementBalance = null,
    Object? difference = null,
    Object? status = null,
    Object? totalDeposits = null,
    Object? totalWithdrawals = null,
    Object? transactionCount = null,
    Object? notes = freezed,
    Object? reconciledBy = null,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_$BankReconciliationImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      bankAccountId: null == bankAccountId
          ? _value.bankAccountId
          : bankAccountId // ignore: cast_nullable_to_non_nullable
              as String,
      tenantId: freezed == tenantId
          ? _value.tenantId
          : tenantId // ignore: cast_nullable_to_non_nullable
              as String?,
      reconciliationDate: freezed == reconciliationDate
          ? _value.reconciliationDate
          : reconciliationDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      systemBalance: null == systemBalance
          ? _value.systemBalance
          : systemBalance // ignore: cast_nullable_to_non_nullable
              as double,
      bankStatementBalance: null == bankStatementBalance
          ? _value.bankStatementBalance
          : bankStatementBalance // ignore: cast_nullable_to_non_nullable
              as double,
      difference: null == difference
          ? _value.difference
          : difference // ignore: cast_nullable_to_non_nullable
              as double,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      totalDeposits: null == totalDeposits
          ? _value.totalDeposits
          : totalDeposits // ignore: cast_nullable_to_non_nullable
              as double,
      totalWithdrawals: null == totalWithdrawals
          ? _value.totalWithdrawals
          : totalWithdrawals // ignore: cast_nullable_to_non_nullable
              as double,
      transactionCount: null == transactionCount
          ? _value.transactionCount
          : transactionCount // ignore: cast_nullable_to_non_nullable
              as int,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      reconciledBy: null == reconciledBy
          ? _value.reconciledBy
          : reconciledBy // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BankReconciliationImpl implements _BankReconciliation {
  const _$BankReconciliationImpl(
      {required this.id,
      @JsonKey(name: 'bank_account_id') this.bankAccountId = '',
      @JsonKey(name: 'tenant_id') this.tenantId,
      @JsonKey(name: 'reconciliation_date') this.reconciliationDate,
      @JsonKey(name: 'system_balance') this.systemBalance = 0.0,
      @JsonKey(name: 'bank_statement_balance') this.bankStatementBalance = 0.0,
      this.difference = 0.0,
      this.status = 'pending',
      @JsonKey(name: 'total_deposits') this.totalDeposits = 0.0,
      @JsonKey(name: 'total_withdrawals') this.totalWithdrawals = 0.0,
      @JsonKey(name: 'transaction_count') this.transactionCount = 0,
      this.notes,
      @JsonKey(name: 'reconciled_by') this.reconciledBy = '',
      @JsonKey(name: 'created_at') this.createdAt,
      @JsonKey(name: 'updated_at') this.updatedAt});

  factory _$BankReconciliationImpl.fromJson(Map<String, dynamic> json) =>
      _$$BankReconciliationImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'bank_account_id')
  final String bankAccountId;
  @override
  @JsonKey(name: 'tenant_id')
  final String? tenantId;
  @override
  @JsonKey(name: 'reconciliation_date')
  final DateTime? reconciliationDate;
  @override
  @JsonKey(name: 'system_balance')
  final double systemBalance;
  @override
  @JsonKey(name: 'bank_statement_balance')
  final double bankStatementBalance;
  @override
  @JsonKey()
  final double difference;
// Computed: systemBalance - bankStatementBalance
  @override
  @JsonKey()
  final String status;
// pending, completed, discrepancy
  @override
  @JsonKey(name: 'total_deposits')
  final double totalDeposits;
  @override
  @JsonKey(name: 'total_withdrawals')
  final double totalWithdrawals;
  @override
  @JsonKey(name: 'transaction_count')
  final int transactionCount;
  @override
  final String? notes;
  @override
  @JsonKey(name: 'reconciled_by')
  final String reconciledBy;
  @override
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  @override
  @JsonKey(name: 'updated_at')
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'BankReconciliation(id: $id, bankAccountId: $bankAccountId, tenantId: $tenantId, reconciliationDate: $reconciliationDate, systemBalance: $systemBalance, bankStatementBalance: $bankStatementBalance, difference: $difference, status: $status, totalDeposits: $totalDeposits, totalWithdrawals: $totalWithdrawals, transactionCount: $transactionCount, notes: $notes, reconciledBy: $reconciledBy, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BankReconciliationImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.bankAccountId, bankAccountId) ||
                other.bankAccountId == bankAccountId) &&
            (identical(other.tenantId, tenantId) ||
                other.tenantId == tenantId) &&
            (identical(other.reconciliationDate, reconciliationDate) ||
                other.reconciliationDate == reconciliationDate) &&
            (identical(other.systemBalance, systemBalance) ||
                other.systemBalance == systemBalance) &&
            (identical(other.bankStatementBalance, bankStatementBalance) ||
                other.bankStatementBalance == bankStatementBalance) &&
            (identical(other.difference, difference) ||
                other.difference == difference) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.totalDeposits, totalDeposits) ||
                other.totalDeposits == totalDeposits) &&
            (identical(other.totalWithdrawals, totalWithdrawals) ||
                other.totalWithdrawals == totalWithdrawals) &&
            (identical(other.transactionCount, transactionCount) ||
                other.transactionCount == transactionCount) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.reconciledBy, reconciledBy) ||
                other.reconciledBy == reconciledBy) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      bankAccountId,
      tenantId,
      reconciliationDate,
      systemBalance,
      bankStatementBalance,
      difference,
      status,
      totalDeposits,
      totalWithdrawals,
      transactionCount,
      notes,
      reconciledBy,
      createdAt,
      updatedAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BankReconciliationImplCopyWith<_$BankReconciliationImpl> get copyWith =>
      __$$BankReconciliationImplCopyWithImpl<_$BankReconciliationImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BankReconciliationImplToJson(
      this,
    );
  }
}

abstract class _BankReconciliation implements BankReconciliation {
  const factory _BankReconciliation(
      {required final String id,
      @JsonKey(name: 'bank_account_id') final String bankAccountId,
      @JsonKey(name: 'tenant_id') final String? tenantId,
      @JsonKey(name: 'reconciliation_date') final DateTime? reconciliationDate,
      @JsonKey(name: 'system_balance') final double systemBalance,
      @JsonKey(name: 'bank_statement_balance')
      final double bankStatementBalance,
      final double difference,
      final String status,
      @JsonKey(name: 'total_deposits') final double totalDeposits,
      @JsonKey(name: 'total_withdrawals') final double totalWithdrawals,
      @JsonKey(name: 'transaction_count') final int transactionCount,
      final String? notes,
      @JsonKey(name: 'reconciled_by') final String reconciledBy,
      @JsonKey(name: 'created_at') final DateTime? createdAt,
      @JsonKey(name: 'updated_at')
      final DateTime? updatedAt}) = _$BankReconciliationImpl;

  factory _BankReconciliation.fromJson(Map<String, dynamic> json) =
      _$BankReconciliationImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'bank_account_id')
  String get bankAccountId;
  @override
  @JsonKey(name: 'tenant_id')
  String? get tenantId;
  @override
  @JsonKey(name: 'reconciliation_date')
  DateTime? get reconciliationDate;
  @override
  @JsonKey(name: 'system_balance')
  double get systemBalance;
  @override
  @JsonKey(name: 'bank_statement_balance')
  double get bankStatementBalance;
  @override
  double get difference;
  @override // Computed: systemBalance - bankStatementBalance
  String get status;
  @override // pending, completed, discrepancy
  @JsonKey(name: 'total_deposits')
  double get totalDeposits;
  @override
  @JsonKey(name: 'total_withdrawals')
  double get totalWithdrawals;
  @override
  @JsonKey(name: 'transaction_count')
  int get transactionCount;
  @override
  String? get notes;
  @override
  @JsonKey(name: 'reconciled_by')
  String get reconciledBy;
  @override
  @JsonKey(name: 'created_at')
  DateTime? get createdAt;
  @override
  @JsonKey(name: 'updated_at')
  DateTime? get updatedAt;
  @override
  @JsonKey(ignore: true)
  _$$BankReconciliationImplCopyWith<_$BankReconciliationImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

BankAccountSummary _$BankAccountSummaryFromJson(Map<String, dynamic> json) {
  return _BankAccountSummary.fromJson(json);
}

/// @nodoc
mixin _$BankAccountSummary {
  TenantBankAccount get account => throw _privateConstructorUsedError;
  double get totalDepositsThisMonth => throw _privateConstructorUsedError;
  double get totalWithdrawalsThisMonth => throw _privateConstructorUsedError;
  int get transactionCount => throw _privateConstructorUsedError;
  double get odUtilizationPercent => throw _privateConstructorUsedError;
  DateTime? get lastReconciliationDate => throw _privateConstructorUsedError;
  String? get lastTransactionDate => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BankAccountSummaryCopyWith<BankAccountSummary> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BankAccountSummaryCopyWith<$Res> {
  factory $BankAccountSummaryCopyWith(
          BankAccountSummary value, $Res Function(BankAccountSummary) then) =
      _$BankAccountSummaryCopyWithImpl<$Res, BankAccountSummary>;
  @useResult
  $Res call(
      {TenantBankAccount account,
      double totalDepositsThisMonth,
      double totalWithdrawalsThisMonth,
      int transactionCount,
      double odUtilizationPercent,
      DateTime? lastReconciliationDate,
      String? lastTransactionDate});

  $TenantBankAccountCopyWith<$Res> get account;
}

/// @nodoc
class _$BankAccountSummaryCopyWithImpl<$Res, $Val extends BankAccountSummary>
    implements $BankAccountSummaryCopyWith<$Res> {
  _$BankAccountSummaryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? account = null,
    Object? totalDepositsThisMonth = null,
    Object? totalWithdrawalsThisMonth = null,
    Object? transactionCount = null,
    Object? odUtilizationPercent = null,
    Object? lastReconciliationDate = freezed,
    Object? lastTransactionDate = freezed,
  }) {
    return _then(_value.copyWith(
      account: null == account
          ? _value.account
          : account // ignore: cast_nullable_to_non_nullable
              as TenantBankAccount,
      totalDepositsThisMonth: null == totalDepositsThisMonth
          ? _value.totalDepositsThisMonth
          : totalDepositsThisMonth // ignore: cast_nullable_to_non_nullable
              as double,
      totalWithdrawalsThisMonth: null == totalWithdrawalsThisMonth
          ? _value.totalWithdrawalsThisMonth
          : totalWithdrawalsThisMonth // ignore: cast_nullable_to_non_nullable
              as double,
      transactionCount: null == transactionCount
          ? _value.transactionCount
          : transactionCount // ignore: cast_nullable_to_non_nullable
              as int,
      odUtilizationPercent: null == odUtilizationPercent
          ? _value.odUtilizationPercent
          : odUtilizationPercent // ignore: cast_nullable_to_non_nullable
              as double,
      lastReconciliationDate: freezed == lastReconciliationDate
          ? _value.lastReconciliationDate
          : lastReconciliationDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastTransactionDate: freezed == lastTransactionDate
          ? _value.lastTransactionDate
          : lastTransactionDate // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $TenantBankAccountCopyWith<$Res> get account {
    return $TenantBankAccountCopyWith<$Res>(_value.account, (value) {
      return _then(_value.copyWith(account: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$BankAccountSummaryImplCopyWith<$Res>
    implements $BankAccountSummaryCopyWith<$Res> {
  factory _$$BankAccountSummaryImplCopyWith(_$BankAccountSummaryImpl value,
          $Res Function(_$BankAccountSummaryImpl) then) =
      __$$BankAccountSummaryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {TenantBankAccount account,
      double totalDepositsThisMonth,
      double totalWithdrawalsThisMonth,
      int transactionCount,
      double odUtilizationPercent,
      DateTime? lastReconciliationDate,
      String? lastTransactionDate});

  @override
  $TenantBankAccountCopyWith<$Res> get account;
}

/// @nodoc
class __$$BankAccountSummaryImplCopyWithImpl<$Res>
    extends _$BankAccountSummaryCopyWithImpl<$Res, _$BankAccountSummaryImpl>
    implements _$$BankAccountSummaryImplCopyWith<$Res> {
  __$$BankAccountSummaryImplCopyWithImpl(_$BankAccountSummaryImpl _value,
      $Res Function(_$BankAccountSummaryImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? account = null,
    Object? totalDepositsThisMonth = null,
    Object? totalWithdrawalsThisMonth = null,
    Object? transactionCount = null,
    Object? odUtilizationPercent = null,
    Object? lastReconciliationDate = freezed,
    Object? lastTransactionDate = freezed,
  }) {
    return _then(_$BankAccountSummaryImpl(
      account: null == account
          ? _value.account
          : account // ignore: cast_nullable_to_non_nullable
              as TenantBankAccount,
      totalDepositsThisMonth: null == totalDepositsThisMonth
          ? _value.totalDepositsThisMonth
          : totalDepositsThisMonth // ignore: cast_nullable_to_non_nullable
              as double,
      totalWithdrawalsThisMonth: null == totalWithdrawalsThisMonth
          ? _value.totalWithdrawalsThisMonth
          : totalWithdrawalsThisMonth // ignore: cast_nullable_to_non_nullable
              as double,
      transactionCount: null == transactionCount
          ? _value.transactionCount
          : transactionCount // ignore: cast_nullable_to_non_nullable
              as int,
      odUtilizationPercent: null == odUtilizationPercent
          ? _value.odUtilizationPercent
          : odUtilizationPercent // ignore: cast_nullable_to_non_nullable
              as double,
      lastReconciliationDate: freezed == lastReconciliationDate
          ? _value.lastReconciliationDate
          : lastReconciliationDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastTransactionDate: freezed == lastTransactionDate
          ? _value.lastTransactionDate
          : lastTransactionDate // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BankAccountSummaryImpl implements _BankAccountSummary {
  const _$BankAccountSummaryImpl(
      {required this.account,
      this.totalDepositsThisMonth = 0.0,
      this.totalWithdrawalsThisMonth = 0.0,
      this.transactionCount = 0,
      this.odUtilizationPercent = 0.0,
      this.lastReconciliationDate,
      this.lastTransactionDate});

  factory _$BankAccountSummaryImpl.fromJson(Map<String, dynamic> json) =>
      _$$BankAccountSummaryImplFromJson(json);

  @override
  final TenantBankAccount account;
  @override
  @JsonKey()
  final double totalDepositsThisMonth;
  @override
  @JsonKey()
  final double totalWithdrawalsThisMonth;
  @override
  @JsonKey()
  final int transactionCount;
  @override
  @JsonKey()
  final double odUtilizationPercent;
  @override
  final DateTime? lastReconciliationDate;
  @override
  final String? lastTransactionDate;

  @override
  String toString() {
    return 'BankAccountSummary(account: $account, totalDepositsThisMonth: $totalDepositsThisMonth, totalWithdrawalsThisMonth: $totalWithdrawalsThisMonth, transactionCount: $transactionCount, odUtilizationPercent: $odUtilizationPercent, lastReconciliationDate: $lastReconciliationDate, lastTransactionDate: $lastTransactionDate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BankAccountSummaryImpl &&
            (identical(other.account, account) || other.account == account) &&
            (identical(other.totalDepositsThisMonth, totalDepositsThisMonth) ||
                other.totalDepositsThisMonth == totalDepositsThisMonth) &&
            (identical(other.totalWithdrawalsThisMonth,
                    totalWithdrawalsThisMonth) ||
                other.totalWithdrawalsThisMonth == totalWithdrawalsThisMonth) &&
            (identical(other.transactionCount, transactionCount) ||
                other.transactionCount == transactionCount) &&
            (identical(other.odUtilizationPercent, odUtilizationPercent) ||
                other.odUtilizationPercent == odUtilizationPercent) &&
            (identical(other.lastReconciliationDate, lastReconciliationDate) ||
                other.lastReconciliationDate == lastReconciliationDate) &&
            (identical(other.lastTransactionDate, lastTransactionDate) ||
                other.lastTransactionDate == lastTransactionDate));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      account,
      totalDepositsThisMonth,
      totalWithdrawalsThisMonth,
      transactionCount,
      odUtilizationPercent,
      lastReconciliationDate,
      lastTransactionDate);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BankAccountSummaryImplCopyWith<_$BankAccountSummaryImpl> get copyWith =>
      __$$BankAccountSummaryImplCopyWithImpl<_$BankAccountSummaryImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BankAccountSummaryImplToJson(
      this,
    );
  }
}

abstract class _BankAccountSummary implements BankAccountSummary {
  const factory _BankAccountSummary(
      {required final TenantBankAccount account,
      final double totalDepositsThisMonth,
      final double totalWithdrawalsThisMonth,
      final int transactionCount,
      final double odUtilizationPercent,
      final DateTime? lastReconciliationDate,
      final String? lastTransactionDate}) = _$BankAccountSummaryImpl;

  factory _BankAccountSummary.fromJson(Map<String, dynamic> json) =
      _$BankAccountSummaryImpl.fromJson;

  @override
  TenantBankAccount get account;
  @override
  double get totalDepositsThisMonth;
  @override
  double get totalWithdrawalsThisMonth;
  @override
  int get transactionCount;
  @override
  double get odUtilizationPercent;
  @override
  DateTime? get lastReconciliationDate;
  @override
  String? get lastTransactionDate;
  @override
  @JsonKey(ignore: true)
  _$$BankAccountSummaryImplCopyWith<_$BankAccountSummaryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

CreateBankAccountRequest _$CreateBankAccountRequestFromJson(
    Map<String, dynamic> json) {
  return _CreateBankAccountRequest.fromJson(json);
}

/// @nodoc
mixin _$CreateBankAccountRequest {
  @JsonKey(name: 'bank_name')
  String get bankName => throw _privateConstructorUsedError;
  @JsonKey(name: 'account_number')
  String get accountNumber => throw _privateConstructorUsedError;
  @JsonKey(name: 'account_holder_name')
  String get accountHolderName => throw _privateConstructorUsedError;
  @JsonKey(name: 'ifsc_code')
  String get ifscCode => throw _privateConstructorUsedError;
  @JsonKey(name: 'branch_name')
  String? get branchName => throw _privateConstructorUsedError;
  @JsonKey(name: 'account_type')
  String get accountType => throw _privateConstructorUsedError;
  @JsonKey(name: 'opening_balance')
  double get openingBalance => throw _privateConstructorUsedError;
  @JsonKey(name: 'od_limit')
  double get odLimit => throw _privateConstructorUsedError;
  @JsonKey(name: 'od_interest_rate')
  double get odInterestRate => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_default')
  bool get isDefault => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_primary')
  bool get isPrimary => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $CreateBankAccountRequestCopyWith<CreateBankAccountRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CreateBankAccountRequestCopyWith<$Res> {
  factory $CreateBankAccountRequestCopyWith(CreateBankAccountRequest value,
          $Res Function(CreateBankAccountRequest) then) =
      _$CreateBankAccountRequestCopyWithImpl<$Res, CreateBankAccountRequest>;
  @useResult
  $Res call(
      {@JsonKey(name: 'bank_name') String bankName,
      @JsonKey(name: 'account_number') String accountNumber,
      @JsonKey(name: 'account_holder_name') String accountHolderName,
      @JsonKey(name: 'ifsc_code') String ifscCode,
      @JsonKey(name: 'branch_name') String? branchName,
      @JsonKey(name: 'account_type') String accountType,
      @JsonKey(name: 'opening_balance') double openingBalance,
      @JsonKey(name: 'od_limit') double odLimit,
      @JsonKey(name: 'od_interest_rate') double odInterestRate,
      @JsonKey(name: 'is_default') bool isDefault,
      @JsonKey(name: 'is_primary') bool isPrimary,
      String? notes});
}

/// @nodoc
class _$CreateBankAccountRequestCopyWithImpl<$Res,
        $Val extends CreateBankAccountRequest>
    implements $CreateBankAccountRequestCopyWith<$Res> {
  _$CreateBankAccountRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bankName = null,
    Object? accountNumber = null,
    Object? accountHolderName = null,
    Object? ifscCode = null,
    Object? branchName = freezed,
    Object? accountType = null,
    Object? openingBalance = null,
    Object? odLimit = null,
    Object? odInterestRate = null,
    Object? isDefault = null,
    Object? isPrimary = null,
    Object? notes = freezed,
  }) {
    return _then(_value.copyWith(
      bankName: null == bankName
          ? _value.bankName
          : bankName // ignore: cast_nullable_to_non_nullable
              as String,
      accountNumber: null == accountNumber
          ? _value.accountNumber
          : accountNumber // ignore: cast_nullable_to_non_nullable
              as String,
      accountHolderName: null == accountHolderName
          ? _value.accountHolderName
          : accountHolderName // ignore: cast_nullable_to_non_nullable
              as String,
      ifscCode: null == ifscCode
          ? _value.ifscCode
          : ifscCode // ignore: cast_nullable_to_non_nullable
              as String,
      branchName: freezed == branchName
          ? _value.branchName
          : branchName // ignore: cast_nullable_to_non_nullable
              as String?,
      accountType: null == accountType
          ? _value.accountType
          : accountType // ignore: cast_nullable_to_non_nullable
              as String,
      openingBalance: null == openingBalance
          ? _value.openingBalance
          : openingBalance // ignore: cast_nullable_to_non_nullable
              as double,
      odLimit: null == odLimit
          ? _value.odLimit
          : odLimit // ignore: cast_nullable_to_non_nullable
              as double,
      odInterestRate: null == odInterestRate
          ? _value.odInterestRate
          : odInterestRate // ignore: cast_nullable_to_non_nullable
              as double,
      isDefault: null == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool,
      isPrimary: null == isPrimary
          ? _value.isPrimary
          : isPrimary // ignore: cast_nullable_to_non_nullable
              as bool,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CreateBankAccountRequestImplCopyWith<$Res>
    implements $CreateBankAccountRequestCopyWith<$Res> {
  factory _$$CreateBankAccountRequestImplCopyWith(
          _$CreateBankAccountRequestImpl value,
          $Res Function(_$CreateBankAccountRequestImpl) then) =
      __$$CreateBankAccountRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'bank_name') String bankName,
      @JsonKey(name: 'account_number') String accountNumber,
      @JsonKey(name: 'account_holder_name') String accountHolderName,
      @JsonKey(name: 'ifsc_code') String ifscCode,
      @JsonKey(name: 'branch_name') String? branchName,
      @JsonKey(name: 'account_type') String accountType,
      @JsonKey(name: 'opening_balance') double openingBalance,
      @JsonKey(name: 'od_limit') double odLimit,
      @JsonKey(name: 'od_interest_rate') double odInterestRate,
      @JsonKey(name: 'is_default') bool isDefault,
      @JsonKey(name: 'is_primary') bool isPrimary,
      String? notes});
}

/// @nodoc
class __$$CreateBankAccountRequestImplCopyWithImpl<$Res>
    extends _$CreateBankAccountRequestCopyWithImpl<$Res,
        _$CreateBankAccountRequestImpl>
    implements _$$CreateBankAccountRequestImplCopyWith<$Res> {
  __$$CreateBankAccountRequestImplCopyWithImpl(
      _$CreateBankAccountRequestImpl _value,
      $Res Function(_$CreateBankAccountRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bankName = null,
    Object? accountNumber = null,
    Object? accountHolderName = null,
    Object? ifscCode = null,
    Object? branchName = freezed,
    Object? accountType = null,
    Object? openingBalance = null,
    Object? odLimit = null,
    Object? odInterestRate = null,
    Object? isDefault = null,
    Object? isPrimary = null,
    Object? notes = freezed,
  }) {
    return _then(_$CreateBankAccountRequestImpl(
      bankName: null == bankName
          ? _value.bankName
          : bankName // ignore: cast_nullable_to_non_nullable
              as String,
      accountNumber: null == accountNumber
          ? _value.accountNumber
          : accountNumber // ignore: cast_nullable_to_non_nullable
              as String,
      accountHolderName: null == accountHolderName
          ? _value.accountHolderName
          : accountHolderName // ignore: cast_nullable_to_non_nullable
              as String,
      ifscCode: null == ifscCode
          ? _value.ifscCode
          : ifscCode // ignore: cast_nullable_to_non_nullable
              as String,
      branchName: freezed == branchName
          ? _value.branchName
          : branchName // ignore: cast_nullable_to_non_nullable
              as String?,
      accountType: null == accountType
          ? _value.accountType
          : accountType // ignore: cast_nullable_to_non_nullable
              as String,
      openingBalance: null == openingBalance
          ? _value.openingBalance
          : openingBalance // ignore: cast_nullable_to_non_nullable
              as double,
      odLimit: null == odLimit
          ? _value.odLimit
          : odLimit // ignore: cast_nullable_to_non_nullable
              as double,
      odInterestRate: null == odInterestRate
          ? _value.odInterestRate
          : odInterestRate // ignore: cast_nullable_to_non_nullable
              as double,
      isDefault: null == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool,
      isPrimary: null == isPrimary
          ? _value.isPrimary
          : isPrimary // ignore: cast_nullable_to_non_nullable
              as bool,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CreateBankAccountRequestImpl implements _CreateBankAccountRequest {
  const _$CreateBankAccountRequestImpl(
      {@JsonKey(name: 'bank_name') required this.bankName,
      @JsonKey(name: 'account_number') required this.accountNumber,
      @JsonKey(name: 'account_holder_name') required this.accountHolderName,
      @JsonKey(name: 'ifsc_code') required this.ifscCode,
      @JsonKey(name: 'branch_name') this.branchName,
      @JsonKey(name: 'account_type') this.accountType = 'savings',
      @JsonKey(name: 'opening_balance') this.openingBalance = 0.0,
      @JsonKey(name: 'od_limit') this.odLimit = 0.0,
      @JsonKey(name: 'od_interest_rate') this.odInterestRate = 0.0,
      @JsonKey(name: 'is_default') this.isDefault = false,
      @JsonKey(name: 'is_primary') this.isPrimary = false,
      this.notes});

  factory _$CreateBankAccountRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$CreateBankAccountRequestImplFromJson(json);

  @override
  @JsonKey(name: 'bank_name')
  final String bankName;
  @override
  @JsonKey(name: 'account_number')
  final String accountNumber;
  @override
  @JsonKey(name: 'account_holder_name')
  final String accountHolderName;
  @override
  @JsonKey(name: 'ifsc_code')
  final String ifscCode;
  @override
  @JsonKey(name: 'branch_name')
  final String? branchName;
  @override
  @JsonKey(name: 'account_type')
  final String accountType;
  @override
  @JsonKey(name: 'opening_balance')
  final double openingBalance;
  @override
  @JsonKey(name: 'od_limit')
  final double odLimit;
  @override
  @JsonKey(name: 'od_interest_rate')
  final double odInterestRate;
  @override
  @JsonKey(name: 'is_default')
  final bool isDefault;
  @override
  @JsonKey(name: 'is_primary')
  final bool isPrimary;
  @override
  final String? notes;

  @override
  String toString() {
    return 'CreateBankAccountRequest(bankName: $bankName, accountNumber: $accountNumber, accountHolderName: $accountHolderName, ifscCode: $ifscCode, branchName: $branchName, accountType: $accountType, openingBalance: $openingBalance, odLimit: $odLimit, odInterestRate: $odInterestRate, isDefault: $isDefault, isPrimary: $isPrimary, notes: $notes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CreateBankAccountRequestImpl &&
            (identical(other.bankName, bankName) ||
                other.bankName == bankName) &&
            (identical(other.accountNumber, accountNumber) ||
                other.accountNumber == accountNumber) &&
            (identical(other.accountHolderName, accountHolderName) ||
                other.accountHolderName == accountHolderName) &&
            (identical(other.ifscCode, ifscCode) ||
                other.ifscCode == ifscCode) &&
            (identical(other.branchName, branchName) ||
                other.branchName == branchName) &&
            (identical(other.accountType, accountType) ||
                other.accountType == accountType) &&
            (identical(other.openingBalance, openingBalance) ||
                other.openingBalance == openingBalance) &&
            (identical(other.odLimit, odLimit) || other.odLimit == odLimit) &&
            (identical(other.odInterestRate, odInterestRate) ||
                other.odInterestRate == odInterestRate) &&
            (identical(other.isDefault, isDefault) ||
                other.isDefault == isDefault) &&
            (identical(other.isPrimary, isPrimary) ||
                other.isPrimary == isPrimary) &&
            (identical(other.notes, notes) || other.notes == notes));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      bankName,
      accountNumber,
      accountHolderName,
      ifscCode,
      branchName,
      accountType,
      openingBalance,
      odLimit,
      odInterestRate,
      isDefault,
      isPrimary,
      notes);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CreateBankAccountRequestImplCopyWith<_$CreateBankAccountRequestImpl>
      get copyWith => __$$CreateBankAccountRequestImplCopyWithImpl<
          _$CreateBankAccountRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CreateBankAccountRequestImplToJson(
      this,
    );
  }
}

abstract class _CreateBankAccountRequest implements CreateBankAccountRequest {
  const factory _CreateBankAccountRequest(
      {@JsonKey(name: 'bank_name') required final String bankName,
      @JsonKey(name: 'account_number') required final String accountNumber,
      @JsonKey(name: 'account_holder_name')
      required final String accountHolderName,
      @JsonKey(name: 'ifsc_code') required final String ifscCode,
      @JsonKey(name: 'branch_name') final String? branchName,
      @JsonKey(name: 'account_type') final String accountType,
      @JsonKey(name: 'opening_balance') final double openingBalance,
      @JsonKey(name: 'od_limit') final double odLimit,
      @JsonKey(name: 'od_interest_rate') final double odInterestRate,
      @JsonKey(name: 'is_default') final bool isDefault,
      @JsonKey(name: 'is_primary') final bool isPrimary,
      final String? notes}) = _$CreateBankAccountRequestImpl;

  factory _CreateBankAccountRequest.fromJson(Map<String, dynamic> json) =
      _$CreateBankAccountRequestImpl.fromJson;

  @override
  @JsonKey(name: 'bank_name')
  String get bankName;
  @override
  @JsonKey(name: 'account_number')
  String get accountNumber;
  @override
  @JsonKey(name: 'account_holder_name')
  String get accountHolderName;
  @override
  @JsonKey(name: 'ifsc_code')
  String get ifscCode;
  @override
  @JsonKey(name: 'branch_name')
  String? get branchName;
  @override
  @JsonKey(name: 'account_type')
  String get accountType;
  @override
  @JsonKey(name: 'opening_balance')
  double get openingBalance;
  @override
  @JsonKey(name: 'od_limit')
  double get odLimit;
  @override
  @JsonKey(name: 'od_interest_rate')
  double get odInterestRate;
  @override
  @JsonKey(name: 'is_default')
  bool get isDefault;
  @override
  @JsonKey(name: 'is_primary')
  bool get isPrimary;
  @override
  String? get notes;
  @override
  @JsonKey(ignore: true)
  _$$CreateBankAccountRequestImplCopyWith<_$CreateBankAccountRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}

UpdateBankAccountRequest _$UpdateBankAccountRequestFromJson(
    Map<String, dynamic> json) {
  return _UpdateBankAccountRequest.fromJson(json);
}

/// @nodoc
mixin _$UpdateBankAccountRequest {
  @JsonKey(name: 'bank_name')
  String? get bankName => throw _privateConstructorUsedError;
  @JsonKey(name: 'account_holder_name')
  String? get accountHolderName => throw _privateConstructorUsedError;
  @JsonKey(name: 'branch_name')
  String? get branchName => throw _privateConstructorUsedError;
  @JsonKey(name: 'od_limit')
  double? get odLimit => throw _privateConstructorUsedError;
  @JsonKey(name: 'od_interest_rate')
  double? get odInterestRate => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_active')
  bool? get isActive => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_default')
  bool? get isDefault => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_primary')
  bool? get isPrimary => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $UpdateBankAccountRequestCopyWith<UpdateBankAccountRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UpdateBankAccountRequestCopyWith<$Res> {
  factory $UpdateBankAccountRequestCopyWith(UpdateBankAccountRequest value,
          $Res Function(UpdateBankAccountRequest) then) =
      _$UpdateBankAccountRequestCopyWithImpl<$Res, UpdateBankAccountRequest>;
  @useResult
  $Res call(
      {@JsonKey(name: 'bank_name') String? bankName,
      @JsonKey(name: 'account_holder_name') String? accountHolderName,
      @JsonKey(name: 'branch_name') String? branchName,
      @JsonKey(name: 'od_limit') double? odLimit,
      @JsonKey(name: 'od_interest_rate') double? odInterestRate,
      @JsonKey(name: 'is_active') bool? isActive,
      @JsonKey(name: 'is_default') bool? isDefault,
      @JsonKey(name: 'is_primary') bool? isPrimary,
      String? notes});
}

/// @nodoc
class _$UpdateBankAccountRequestCopyWithImpl<$Res,
        $Val extends UpdateBankAccountRequest>
    implements $UpdateBankAccountRequestCopyWith<$Res> {
  _$UpdateBankAccountRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bankName = freezed,
    Object? accountHolderName = freezed,
    Object? branchName = freezed,
    Object? odLimit = freezed,
    Object? odInterestRate = freezed,
    Object? isActive = freezed,
    Object? isDefault = freezed,
    Object? isPrimary = freezed,
    Object? notes = freezed,
  }) {
    return _then(_value.copyWith(
      bankName: freezed == bankName
          ? _value.bankName
          : bankName // ignore: cast_nullable_to_non_nullable
              as String?,
      accountHolderName: freezed == accountHolderName
          ? _value.accountHolderName
          : accountHolderName // ignore: cast_nullable_to_non_nullable
              as String?,
      branchName: freezed == branchName
          ? _value.branchName
          : branchName // ignore: cast_nullable_to_non_nullable
              as String?,
      odLimit: freezed == odLimit
          ? _value.odLimit
          : odLimit // ignore: cast_nullable_to_non_nullable
              as double?,
      odInterestRate: freezed == odInterestRate
          ? _value.odInterestRate
          : odInterestRate // ignore: cast_nullable_to_non_nullable
              as double?,
      isActive: freezed == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool?,
      isDefault: freezed == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool?,
      isPrimary: freezed == isPrimary
          ? _value.isPrimary
          : isPrimary // ignore: cast_nullable_to_non_nullable
              as bool?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$UpdateBankAccountRequestImplCopyWith<$Res>
    implements $UpdateBankAccountRequestCopyWith<$Res> {
  factory _$$UpdateBankAccountRequestImplCopyWith(
          _$UpdateBankAccountRequestImpl value,
          $Res Function(_$UpdateBankAccountRequestImpl) then) =
      __$$UpdateBankAccountRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'bank_name') String? bankName,
      @JsonKey(name: 'account_holder_name') String? accountHolderName,
      @JsonKey(name: 'branch_name') String? branchName,
      @JsonKey(name: 'od_limit') double? odLimit,
      @JsonKey(name: 'od_interest_rate') double? odInterestRate,
      @JsonKey(name: 'is_active') bool? isActive,
      @JsonKey(name: 'is_default') bool? isDefault,
      @JsonKey(name: 'is_primary') bool? isPrimary,
      String? notes});
}

/// @nodoc
class __$$UpdateBankAccountRequestImplCopyWithImpl<$Res>
    extends _$UpdateBankAccountRequestCopyWithImpl<$Res,
        _$UpdateBankAccountRequestImpl>
    implements _$$UpdateBankAccountRequestImplCopyWith<$Res> {
  __$$UpdateBankAccountRequestImplCopyWithImpl(
      _$UpdateBankAccountRequestImpl _value,
      $Res Function(_$UpdateBankAccountRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bankName = freezed,
    Object? accountHolderName = freezed,
    Object? branchName = freezed,
    Object? odLimit = freezed,
    Object? odInterestRate = freezed,
    Object? isActive = freezed,
    Object? isDefault = freezed,
    Object? isPrimary = freezed,
    Object? notes = freezed,
  }) {
    return _then(_$UpdateBankAccountRequestImpl(
      bankName: freezed == bankName
          ? _value.bankName
          : bankName // ignore: cast_nullable_to_non_nullable
              as String?,
      accountHolderName: freezed == accountHolderName
          ? _value.accountHolderName
          : accountHolderName // ignore: cast_nullable_to_non_nullable
              as String?,
      branchName: freezed == branchName
          ? _value.branchName
          : branchName // ignore: cast_nullable_to_non_nullable
              as String?,
      odLimit: freezed == odLimit
          ? _value.odLimit
          : odLimit // ignore: cast_nullable_to_non_nullable
              as double?,
      odInterestRate: freezed == odInterestRate
          ? _value.odInterestRate
          : odInterestRate // ignore: cast_nullable_to_non_nullable
              as double?,
      isActive: freezed == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool?,
      isDefault: freezed == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool?,
      isPrimary: freezed == isPrimary
          ? _value.isPrimary
          : isPrimary // ignore: cast_nullable_to_non_nullable
              as bool?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$UpdateBankAccountRequestImpl implements _UpdateBankAccountRequest {
  const _$UpdateBankAccountRequestImpl(
      {@JsonKey(name: 'bank_name') this.bankName,
      @JsonKey(name: 'account_holder_name') this.accountHolderName,
      @JsonKey(name: 'branch_name') this.branchName,
      @JsonKey(name: 'od_limit') this.odLimit,
      @JsonKey(name: 'od_interest_rate') this.odInterestRate,
      @JsonKey(name: 'is_active') this.isActive,
      @JsonKey(name: 'is_default') this.isDefault,
      @JsonKey(name: 'is_primary') this.isPrimary,
      this.notes});

  factory _$UpdateBankAccountRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$UpdateBankAccountRequestImplFromJson(json);

  @override
  @JsonKey(name: 'bank_name')
  final String? bankName;
  @override
  @JsonKey(name: 'account_holder_name')
  final String? accountHolderName;
  @override
  @JsonKey(name: 'branch_name')
  final String? branchName;
  @override
  @JsonKey(name: 'od_limit')
  final double? odLimit;
  @override
  @JsonKey(name: 'od_interest_rate')
  final double? odInterestRate;
  @override
  @JsonKey(name: 'is_active')
  final bool? isActive;
  @override
  @JsonKey(name: 'is_default')
  final bool? isDefault;
  @override
  @JsonKey(name: 'is_primary')
  final bool? isPrimary;
  @override
  final String? notes;

  @override
  String toString() {
    return 'UpdateBankAccountRequest(bankName: $bankName, accountHolderName: $accountHolderName, branchName: $branchName, odLimit: $odLimit, odInterestRate: $odInterestRate, isActive: $isActive, isDefault: $isDefault, isPrimary: $isPrimary, notes: $notes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UpdateBankAccountRequestImpl &&
            (identical(other.bankName, bankName) ||
                other.bankName == bankName) &&
            (identical(other.accountHolderName, accountHolderName) ||
                other.accountHolderName == accountHolderName) &&
            (identical(other.branchName, branchName) ||
                other.branchName == branchName) &&
            (identical(other.odLimit, odLimit) || other.odLimit == odLimit) &&
            (identical(other.odInterestRate, odInterestRate) ||
                other.odInterestRate == odInterestRate) &&
            (identical(other.isActive, isActive) ||
                other.isActive == isActive) &&
            (identical(other.isDefault, isDefault) ||
                other.isDefault == isDefault) &&
            (identical(other.isPrimary, isPrimary) ||
                other.isPrimary == isPrimary) &&
            (identical(other.notes, notes) || other.notes == notes));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      bankName,
      accountHolderName,
      branchName,
      odLimit,
      odInterestRate,
      isActive,
      isDefault,
      isPrimary,
      notes);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$UpdateBankAccountRequestImplCopyWith<_$UpdateBankAccountRequestImpl>
      get copyWith => __$$UpdateBankAccountRequestImplCopyWithImpl<
          _$UpdateBankAccountRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UpdateBankAccountRequestImplToJson(
      this,
    );
  }
}

abstract class _UpdateBankAccountRequest implements UpdateBankAccountRequest {
  const factory _UpdateBankAccountRequest(
      {@JsonKey(name: 'bank_name') final String? bankName,
      @JsonKey(name: 'account_holder_name') final String? accountHolderName,
      @JsonKey(name: 'branch_name') final String? branchName,
      @JsonKey(name: 'od_limit') final double? odLimit,
      @JsonKey(name: 'od_interest_rate') final double? odInterestRate,
      @JsonKey(name: 'is_active') final bool? isActive,
      @JsonKey(name: 'is_default') final bool? isDefault,
      @JsonKey(name: 'is_primary') final bool? isPrimary,
      final String? notes}) = _$UpdateBankAccountRequestImpl;

  factory _UpdateBankAccountRequest.fromJson(Map<String, dynamic> json) =
      _$UpdateBankAccountRequestImpl.fromJson;

  @override
  @JsonKey(name: 'bank_name')
  String? get bankName;
  @override
  @JsonKey(name: 'account_holder_name')
  String? get accountHolderName;
  @override
  @JsonKey(name: 'branch_name')
  String? get branchName;
  @override
  @JsonKey(name: 'od_limit')
  double? get odLimit;
  @override
  @JsonKey(name: 'od_interest_rate')
  double? get odInterestRate;
  @override
  @JsonKey(name: 'is_active')
  bool? get isActive;
  @override
  @JsonKey(name: 'is_default')
  bool? get isDefault;
  @override
  @JsonKey(name: 'is_primary')
  bool? get isPrimary;
  @override
  String? get notes;
  @override
  @JsonKey(ignore: true)
  _$$UpdateBankAccountRequestImplCopyWith<_$UpdateBankAccountRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}

RecordBankTransactionRequest _$RecordBankTransactionRequestFromJson(
    Map<String, dynamic> json) {
  return _RecordBankTransactionRequest.fromJson(json);
}

/// @nodoc
mixin _$RecordBankTransactionRequest {
  @JsonKey(name: 'transaction_type')
  String get transactionType => throw _privateConstructorUsedError;
  double get amount => throw _privateConstructorUsedError;
  @JsonKey(name: 'bank_reference_no')
  String? get bankReferenceNo => throw _privateConstructorUsedError;
  @JsonKey(name: 'transaction_date', toJson: _dateTimeToJson)
  DateTime? get transactionDate => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $RecordBankTransactionRequestCopyWith<RecordBankTransactionRequest>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RecordBankTransactionRequestCopyWith<$Res> {
  factory $RecordBankTransactionRequestCopyWith(
          RecordBankTransactionRequest value,
          $Res Function(RecordBankTransactionRequest) then) =
      _$RecordBankTransactionRequestCopyWithImpl<$Res,
          RecordBankTransactionRequest>;
  @useResult
  $Res call(
      {@JsonKey(name: 'transaction_type') String transactionType,
      double amount,
      @JsonKey(name: 'bank_reference_no') String? bankReferenceNo,
      @JsonKey(name: 'transaction_date', toJson: _dateTimeToJson)
      DateTime? transactionDate,
      String? description,
      String? notes});
}

/// @nodoc
class _$RecordBankTransactionRequestCopyWithImpl<$Res,
        $Val extends RecordBankTransactionRequest>
    implements $RecordBankTransactionRequestCopyWith<$Res> {
  _$RecordBankTransactionRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? transactionType = null,
    Object? amount = null,
    Object? bankReferenceNo = freezed,
    Object? transactionDate = freezed,
    Object? description = freezed,
    Object? notes = freezed,
  }) {
    return _then(_value.copyWith(
      transactionType: null == transactionType
          ? _value.transactionType
          : transactionType // ignore: cast_nullable_to_non_nullable
              as String,
      amount: null == amount
          ? _value.amount
          : amount // ignore: cast_nullable_to_non_nullable
              as double,
      bankReferenceNo: freezed == bankReferenceNo
          ? _value.bankReferenceNo
          : bankReferenceNo // ignore: cast_nullable_to_non_nullable
              as String?,
      transactionDate: freezed == transactionDate
          ? _value.transactionDate
          : transactionDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RecordBankTransactionRequestImplCopyWith<$Res>
    implements $RecordBankTransactionRequestCopyWith<$Res> {
  factory _$$RecordBankTransactionRequestImplCopyWith(
          _$RecordBankTransactionRequestImpl value,
          $Res Function(_$RecordBankTransactionRequestImpl) then) =
      __$$RecordBankTransactionRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'transaction_type') String transactionType,
      double amount,
      @JsonKey(name: 'bank_reference_no') String? bankReferenceNo,
      @JsonKey(name: 'transaction_date', toJson: _dateTimeToJson)
      DateTime? transactionDate,
      String? description,
      String? notes});
}

/// @nodoc
class __$$RecordBankTransactionRequestImplCopyWithImpl<$Res>
    extends _$RecordBankTransactionRequestCopyWithImpl<$Res,
        _$RecordBankTransactionRequestImpl>
    implements _$$RecordBankTransactionRequestImplCopyWith<$Res> {
  __$$RecordBankTransactionRequestImplCopyWithImpl(
      _$RecordBankTransactionRequestImpl _value,
      $Res Function(_$RecordBankTransactionRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? transactionType = null,
    Object? amount = null,
    Object? bankReferenceNo = freezed,
    Object? transactionDate = freezed,
    Object? description = freezed,
    Object? notes = freezed,
  }) {
    return _then(_$RecordBankTransactionRequestImpl(
      transactionType: null == transactionType
          ? _value.transactionType
          : transactionType // ignore: cast_nullable_to_non_nullable
              as String,
      amount: null == amount
          ? _value.amount
          : amount // ignore: cast_nullable_to_non_nullable
              as double,
      bankReferenceNo: freezed == bankReferenceNo
          ? _value.bankReferenceNo
          : bankReferenceNo // ignore: cast_nullable_to_non_nullable
              as String?,
      transactionDate: freezed == transactionDate
          ? _value.transactionDate
          : transactionDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RecordBankTransactionRequestImpl
    implements _RecordBankTransactionRequest {
  const _$RecordBankTransactionRequestImpl(
      {@JsonKey(name: 'transaction_type') required this.transactionType,
      required this.amount,
      @JsonKey(name: 'bank_reference_no') this.bankReferenceNo,
      @JsonKey(name: 'transaction_date', toJson: _dateTimeToJson)
      this.transactionDate,
      this.description,
      this.notes});

  factory _$RecordBankTransactionRequestImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$RecordBankTransactionRequestImplFromJson(json);

  @override
  @JsonKey(name: 'transaction_type')
  final String transactionType;
  @override
  final double amount;
  @override
  @JsonKey(name: 'bank_reference_no')
  final String? bankReferenceNo;
  @override
  @JsonKey(name: 'transaction_date', toJson: _dateTimeToJson)
  final DateTime? transactionDate;
  @override
  final String? description;
  @override
  final String? notes;

  @override
  String toString() {
    return 'RecordBankTransactionRequest(transactionType: $transactionType, amount: $amount, bankReferenceNo: $bankReferenceNo, transactionDate: $transactionDate, description: $description, notes: $notes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RecordBankTransactionRequestImpl &&
            (identical(other.transactionType, transactionType) ||
                other.transactionType == transactionType) &&
            (identical(other.amount, amount) || other.amount == amount) &&
            (identical(other.bankReferenceNo, bankReferenceNo) ||
                other.bankReferenceNo == bankReferenceNo) &&
            (identical(other.transactionDate, transactionDate) ||
                other.transactionDate == transactionDate) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.notes, notes) || other.notes == notes));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, transactionType, amount,
      bankReferenceNo, transactionDate, description, notes);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$RecordBankTransactionRequestImplCopyWith<
          _$RecordBankTransactionRequestImpl>
      get copyWith => __$$RecordBankTransactionRequestImplCopyWithImpl<
          _$RecordBankTransactionRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RecordBankTransactionRequestImplToJson(
      this,
    );
  }
}

abstract class _RecordBankTransactionRequest
    implements RecordBankTransactionRequest {
  const factory _RecordBankTransactionRequest(
      {@JsonKey(name: 'transaction_type') required final String transactionType,
      required final double amount,
      @JsonKey(name: 'bank_reference_no') final String? bankReferenceNo,
      @JsonKey(name: 'transaction_date', toJson: _dateTimeToJson)
      final DateTime? transactionDate,
      final String? description,
      final String? notes}) = _$RecordBankTransactionRequestImpl;

  factory _RecordBankTransactionRequest.fromJson(Map<String, dynamic> json) =
      _$RecordBankTransactionRequestImpl.fromJson;

  @override
  @JsonKey(name: 'transaction_type')
  String get transactionType;
  @override
  double get amount;
  @override
  @JsonKey(name: 'bank_reference_no')
  String? get bankReferenceNo;
  @override
  @JsonKey(name: 'transaction_date', toJson: _dateTimeToJson)
  DateTime? get transactionDate;
  @override
  String? get description;
  @override
  String? get notes;
  @override
  @JsonKey(ignore: true)
  _$$RecordBankTransactionRequestImplCopyWith<
          _$RecordBankTransactionRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}

CreateBankReconciliationRequest _$CreateBankReconciliationRequestFromJson(
    Map<String, dynamic> json) {
  return _CreateBankReconciliationRequest.fromJson(json);
}

/// @nodoc
mixin _$CreateBankReconciliationRequest {
  double get bankStatementBalance => throw _privateConstructorUsedError;
  DateTime get reconciliationDate => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $CreateBankReconciliationRequestCopyWith<CreateBankReconciliationRequest>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CreateBankReconciliationRequestCopyWith<$Res> {
  factory $CreateBankReconciliationRequestCopyWith(
          CreateBankReconciliationRequest value,
          $Res Function(CreateBankReconciliationRequest) then) =
      _$CreateBankReconciliationRequestCopyWithImpl<$Res,
          CreateBankReconciliationRequest>;
  @useResult
  $Res call(
      {double bankStatementBalance,
      DateTime reconciliationDate,
      String? notes});
}

/// @nodoc
class _$CreateBankReconciliationRequestCopyWithImpl<$Res,
        $Val extends CreateBankReconciliationRequest>
    implements $CreateBankReconciliationRequestCopyWith<$Res> {
  _$CreateBankReconciliationRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bankStatementBalance = null,
    Object? reconciliationDate = null,
    Object? notes = freezed,
  }) {
    return _then(_value.copyWith(
      bankStatementBalance: null == bankStatementBalance
          ? _value.bankStatementBalance
          : bankStatementBalance // ignore: cast_nullable_to_non_nullable
              as double,
      reconciliationDate: null == reconciliationDate
          ? _value.reconciliationDate
          : reconciliationDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CreateBankReconciliationRequestImplCopyWith<$Res>
    implements $CreateBankReconciliationRequestCopyWith<$Res> {
  factory _$$CreateBankReconciliationRequestImplCopyWith(
          _$CreateBankReconciliationRequestImpl value,
          $Res Function(_$CreateBankReconciliationRequestImpl) then) =
      __$$CreateBankReconciliationRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double bankStatementBalance,
      DateTime reconciliationDate,
      String? notes});
}

/// @nodoc
class __$$CreateBankReconciliationRequestImplCopyWithImpl<$Res>
    extends _$CreateBankReconciliationRequestCopyWithImpl<$Res,
        _$CreateBankReconciliationRequestImpl>
    implements _$$CreateBankReconciliationRequestImplCopyWith<$Res> {
  __$$CreateBankReconciliationRequestImplCopyWithImpl(
      _$CreateBankReconciliationRequestImpl _value,
      $Res Function(_$CreateBankReconciliationRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bankStatementBalance = null,
    Object? reconciliationDate = null,
    Object? notes = freezed,
  }) {
    return _then(_$CreateBankReconciliationRequestImpl(
      bankStatementBalance: null == bankStatementBalance
          ? _value.bankStatementBalance
          : bankStatementBalance // ignore: cast_nullable_to_non_nullable
              as double,
      reconciliationDate: null == reconciliationDate
          ? _value.reconciliationDate
          : reconciliationDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CreateBankReconciliationRequestImpl
    implements _CreateBankReconciliationRequest {
  const _$CreateBankReconciliationRequestImpl(
      {required this.bankStatementBalance,
      required this.reconciliationDate,
      this.notes});

  factory _$CreateBankReconciliationRequestImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$CreateBankReconciliationRequestImplFromJson(json);

  @override
  final double bankStatementBalance;
  @override
  final DateTime reconciliationDate;
  @override
  final String? notes;

  @override
  String toString() {
    return 'CreateBankReconciliationRequest(bankStatementBalance: $bankStatementBalance, reconciliationDate: $reconciliationDate, notes: $notes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CreateBankReconciliationRequestImpl &&
            (identical(other.bankStatementBalance, bankStatementBalance) ||
                other.bankStatementBalance == bankStatementBalance) &&
            (identical(other.reconciliationDate, reconciliationDate) ||
                other.reconciliationDate == reconciliationDate) &&
            (identical(other.notes, notes) || other.notes == notes));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, bankStatementBalance, reconciliationDate, notes);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CreateBankReconciliationRequestImplCopyWith<
          _$CreateBankReconciliationRequestImpl>
      get copyWith => __$$CreateBankReconciliationRequestImplCopyWithImpl<
          _$CreateBankReconciliationRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CreateBankReconciliationRequestImplToJson(
      this,
    );
  }
}

abstract class _CreateBankReconciliationRequest
    implements CreateBankReconciliationRequest {
  const factory _CreateBankReconciliationRequest(
      {required final double bankStatementBalance,
      required final DateTime reconciliationDate,
      final String? notes}) = _$CreateBankReconciliationRequestImpl;

  factory _CreateBankReconciliationRequest.fromJson(Map<String, dynamic> json) =
      _$CreateBankReconciliationRequestImpl.fromJson;

  @override
  double get bankStatementBalance;
  @override
  DateTime get reconciliationDate;
  @override
  String? get notes;
  @override
  @JsonKey(ignore: true)
  _$$CreateBankReconciliationRequestImplCopyWith<
          _$CreateBankReconciliationRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}

BankAccountResponse _$BankAccountResponseFromJson(Map<String, dynamic> json) {
  return _BankAccountResponse.fromJson(json);
}

/// @nodoc
mixin _$BankAccountResponse {
  @JsonKey(name: 'bank_account')
  TenantBankAccount get bankAccount => throw _privateConstructorUsedError;
  String? get message => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BankAccountResponseCopyWith<BankAccountResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BankAccountResponseCopyWith<$Res> {
  factory $BankAccountResponseCopyWith(
          BankAccountResponse value, $Res Function(BankAccountResponse) then) =
      _$BankAccountResponseCopyWithImpl<$Res, BankAccountResponse>;
  @useResult
  $Res call(
      {@JsonKey(name: 'bank_account') TenantBankAccount bankAccount,
      String? message});

  $TenantBankAccountCopyWith<$Res> get bankAccount;
}

/// @nodoc
class _$BankAccountResponseCopyWithImpl<$Res, $Val extends BankAccountResponse>
    implements $BankAccountResponseCopyWith<$Res> {
  _$BankAccountResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bankAccount = null,
    Object? message = freezed,
  }) {
    return _then(_value.copyWith(
      bankAccount: null == bankAccount
          ? _value.bankAccount
          : bankAccount // ignore: cast_nullable_to_non_nullable
              as TenantBankAccount,
      message: freezed == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $TenantBankAccountCopyWith<$Res> get bankAccount {
    return $TenantBankAccountCopyWith<$Res>(_value.bankAccount, (value) {
      return _then(_value.copyWith(bankAccount: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$BankAccountResponseImplCopyWith<$Res>
    implements $BankAccountResponseCopyWith<$Res> {
  factory _$$BankAccountResponseImplCopyWith(_$BankAccountResponseImpl value,
          $Res Function(_$BankAccountResponseImpl) then) =
      __$$BankAccountResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'bank_account') TenantBankAccount bankAccount,
      String? message});

  @override
  $TenantBankAccountCopyWith<$Res> get bankAccount;
}

/// @nodoc
class __$$BankAccountResponseImplCopyWithImpl<$Res>
    extends _$BankAccountResponseCopyWithImpl<$Res, _$BankAccountResponseImpl>
    implements _$$BankAccountResponseImplCopyWith<$Res> {
  __$$BankAccountResponseImplCopyWithImpl(_$BankAccountResponseImpl _value,
      $Res Function(_$BankAccountResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bankAccount = null,
    Object? message = freezed,
  }) {
    return _then(_$BankAccountResponseImpl(
      bankAccount: null == bankAccount
          ? _value.bankAccount
          : bankAccount // ignore: cast_nullable_to_non_nullable
              as TenantBankAccount,
      message: freezed == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BankAccountResponseImpl implements _BankAccountResponse {
  const _$BankAccountResponseImpl(
      {@JsonKey(name: 'bank_account') required this.bankAccount, this.message});

  factory _$BankAccountResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$BankAccountResponseImplFromJson(json);

  @override
  @JsonKey(name: 'bank_account')
  final TenantBankAccount bankAccount;
  @override
  final String? message;

  @override
  String toString() {
    return 'BankAccountResponse(bankAccount: $bankAccount, message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BankAccountResponseImpl &&
            (identical(other.bankAccount, bankAccount) ||
                other.bankAccount == bankAccount) &&
            (identical(other.message, message) || other.message == message));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, bankAccount, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BankAccountResponseImplCopyWith<_$BankAccountResponseImpl> get copyWith =>
      __$$BankAccountResponseImplCopyWithImpl<_$BankAccountResponseImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BankAccountResponseImplToJson(
      this,
    );
  }
}

abstract class _BankAccountResponse implements BankAccountResponse {
  const factory _BankAccountResponse(
      {@JsonKey(name: 'bank_account')
      required final TenantBankAccount bankAccount,
      final String? message}) = _$BankAccountResponseImpl;

  factory _BankAccountResponse.fromJson(Map<String, dynamic> json) =
      _$BankAccountResponseImpl.fromJson;

  @override
  @JsonKey(name: 'bank_account')
  TenantBankAccount get bankAccount;
  @override
  String? get message;
  @override
  @JsonKey(ignore: true)
  _$$BankAccountResponseImplCopyWith<_$BankAccountResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

BankAccountsListResponse _$BankAccountsListResponseFromJson(
    Map<String, dynamic> json) {
  return _BankAccountsListResponse.fromJson(json);
}

/// @nodoc
mixin _$BankAccountsListResponse {
  @JsonKey(name: 'bank_accounts')
  List<TenantBankAccount> get bankAccounts =>
      throw _privateConstructorUsedError;
  int get count => throw _privateConstructorUsedError;
  int get total => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_count')
  int get totalCount => throw _privateConstructorUsedError;
  int get page => throw _privateConstructorUsedError;
  @JsonKey(name: 'page_size')
  int get pageSize => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_pages')
  int get totalPages => throw _privateConstructorUsedError;
  @JsonKey(name: 'tenant_id')
  String? get tenantId => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BankAccountsListResponseCopyWith<BankAccountsListResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BankAccountsListResponseCopyWith<$Res> {
  factory $BankAccountsListResponseCopyWith(BankAccountsListResponse value,
          $Res Function(BankAccountsListResponse) then) =
      _$BankAccountsListResponseCopyWithImpl<$Res, BankAccountsListResponse>;
  @useResult
  $Res call(
      {@JsonKey(name: 'bank_accounts') List<TenantBankAccount> bankAccounts,
      int count,
      int total,
      @JsonKey(name: 'total_count') int totalCount,
      int page,
      @JsonKey(name: 'page_size') int pageSize,
      @JsonKey(name: 'total_pages') int totalPages,
      @JsonKey(name: 'tenant_id') String? tenantId});
}

/// @nodoc
class _$BankAccountsListResponseCopyWithImpl<$Res,
        $Val extends BankAccountsListResponse>
    implements $BankAccountsListResponseCopyWith<$Res> {
  _$BankAccountsListResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bankAccounts = null,
    Object? count = null,
    Object? total = null,
    Object? totalCount = null,
    Object? page = null,
    Object? pageSize = null,
    Object? totalPages = null,
    Object? tenantId = freezed,
  }) {
    return _then(_value.copyWith(
      bankAccounts: null == bankAccounts
          ? _value.bankAccounts
          : bankAccounts // ignore: cast_nullable_to_non_nullable
              as List<TenantBankAccount>,
      count: null == count
          ? _value.count
          : count // ignore: cast_nullable_to_non_nullable
              as int,
      total: null == total
          ? _value.total
          : total // ignore: cast_nullable_to_non_nullable
              as int,
      totalCount: null == totalCount
          ? _value.totalCount
          : totalCount // ignore: cast_nullable_to_non_nullable
              as int,
      page: null == page
          ? _value.page
          : page // ignore: cast_nullable_to_non_nullable
              as int,
      pageSize: null == pageSize
          ? _value.pageSize
          : pageSize // ignore: cast_nullable_to_non_nullable
              as int,
      totalPages: null == totalPages
          ? _value.totalPages
          : totalPages // ignore: cast_nullable_to_non_nullable
              as int,
      tenantId: freezed == tenantId
          ? _value.tenantId
          : tenantId // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BankAccountsListResponseImplCopyWith<$Res>
    implements $BankAccountsListResponseCopyWith<$Res> {
  factory _$$BankAccountsListResponseImplCopyWith(
          _$BankAccountsListResponseImpl value,
          $Res Function(_$BankAccountsListResponseImpl) then) =
      __$$BankAccountsListResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'bank_accounts') List<TenantBankAccount> bankAccounts,
      int count,
      int total,
      @JsonKey(name: 'total_count') int totalCount,
      int page,
      @JsonKey(name: 'page_size') int pageSize,
      @JsonKey(name: 'total_pages') int totalPages,
      @JsonKey(name: 'tenant_id') String? tenantId});
}

/// @nodoc
class __$$BankAccountsListResponseImplCopyWithImpl<$Res>
    extends _$BankAccountsListResponseCopyWithImpl<$Res,
        _$BankAccountsListResponseImpl>
    implements _$$BankAccountsListResponseImplCopyWith<$Res> {
  __$$BankAccountsListResponseImplCopyWithImpl(
      _$BankAccountsListResponseImpl _value,
      $Res Function(_$BankAccountsListResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bankAccounts = null,
    Object? count = null,
    Object? total = null,
    Object? totalCount = null,
    Object? page = null,
    Object? pageSize = null,
    Object? totalPages = null,
    Object? tenantId = freezed,
  }) {
    return _then(_$BankAccountsListResponseImpl(
      bankAccounts: null == bankAccounts
          ? _value._bankAccounts
          : bankAccounts // ignore: cast_nullable_to_non_nullable
              as List<TenantBankAccount>,
      count: null == count
          ? _value.count
          : count // ignore: cast_nullable_to_non_nullable
              as int,
      total: null == total
          ? _value.total
          : total // ignore: cast_nullable_to_non_nullable
              as int,
      totalCount: null == totalCount
          ? _value.totalCount
          : totalCount // ignore: cast_nullable_to_non_nullable
              as int,
      page: null == page
          ? _value.page
          : page // ignore: cast_nullable_to_non_nullable
              as int,
      pageSize: null == pageSize
          ? _value.pageSize
          : pageSize // ignore: cast_nullable_to_non_nullable
              as int,
      totalPages: null == totalPages
          ? _value.totalPages
          : totalPages // ignore: cast_nullable_to_non_nullable
              as int,
      tenantId: freezed == tenantId
          ? _value.tenantId
          : tenantId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BankAccountsListResponseImpl implements _BankAccountsListResponse {
  const _$BankAccountsListResponseImpl(
      {@JsonKey(name: 'bank_accounts')
      final List<TenantBankAccount> bankAccounts = const [],
      this.count = 0,
      this.total = 0,
      @JsonKey(name: 'total_count') this.totalCount = 0,
      this.page = 1,
      @JsonKey(name: 'page_size') this.pageSize = 100,
      @JsonKey(name: 'total_pages') this.totalPages = 1,
      @JsonKey(name: 'tenant_id') this.tenantId})
      : _bankAccounts = bankAccounts;

  factory _$BankAccountsListResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$BankAccountsListResponseImplFromJson(json);

  final List<TenantBankAccount> _bankAccounts;
  @override
  @JsonKey(name: 'bank_accounts')
  List<TenantBankAccount> get bankAccounts {
    if (_bankAccounts is EqualUnmodifiableListView) return _bankAccounts;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_bankAccounts);
  }

  @override
  @JsonKey()
  final int count;
  @override
  @JsonKey()
  final int total;
  @override
  @JsonKey(name: 'total_count')
  final int totalCount;
  @override
  @JsonKey()
  final int page;
  @override
  @JsonKey(name: 'page_size')
  final int pageSize;
  @override
  @JsonKey(name: 'total_pages')
  final int totalPages;
  @override
  @JsonKey(name: 'tenant_id')
  final String? tenantId;

  @override
  String toString() {
    return 'BankAccountsListResponse(bankAccounts: $bankAccounts, count: $count, total: $total, totalCount: $totalCount, page: $page, pageSize: $pageSize, totalPages: $totalPages, tenantId: $tenantId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BankAccountsListResponseImpl &&
            const DeepCollectionEquality()
                .equals(other._bankAccounts, _bankAccounts) &&
            (identical(other.count, count) || other.count == count) &&
            (identical(other.total, total) || other.total == total) &&
            (identical(other.totalCount, totalCount) ||
                other.totalCount == totalCount) &&
            (identical(other.page, page) || other.page == page) &&
            (identical(other.pageSize, pageSize) ||
                other.pageSize == pageSize) &&
            (identical(other.totalPages, totalPages) ||
                other.totalPages == totalPages) &&
            (identical(other.tenantId, tenantId) ||
                other.tenantId == tenantId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_bankAccounts),
      count,
      total,
      totalCount,
      page,
      pageSize,
      totalPages,
      tenantId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BankAccountsListResponseImplCopyWith<_$BankAccountsListResponseImpl>
      get copyWith => __$$BankAccountsListResponseImplCopyWithImpl<
          _$BankAccountsListResponseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BankAccountsListResponseImplToJson(
      this,
    );
  }
}

abstract class _BankAccountsListResponse implements BankAccountsListResponse {
  const factory _BankAccountsListResponse(
          {@JsonKey(name: 'bank_accounts')
          final List<TenantBankAccount> bankAccounts,
          final int count,
          final int total,
          @JsonKey(name: 'total_count') final int totalCount,
          final int page,
          @JsonKey(name: 'page_size') final int pageSize,
          @JsonKey(name: 'total_pages') final int totalPages,
          @JsonKey(name: 'tenant_id') final String? tenantId}) =
      _$BankAccountsListResponseImpl;

  factory _BankAccountsListResponse.fromJson(Map<String, dynamic> json) =
      _$BankAccountsListResponseImpl.fromJson;

  @override
  @JsonKey(name: 'bank_accounts')
  List<TenantBankAccount> get bankAccounts;
  @override
  int get count;
  @override
  int get total;
  @override
  @JsonKey(name: 'total_count')
  int get totalCount;
  @override
  int get page;
  @override
  @JsonKey(name: 'page_size')
  int get pageSize;
  @override
  @JsonKey(name: 'total_pages')
  int get totalPages;
  @override
  @JsonKey(name: 'tenant_id')
  String? get tenantId;
  @override
  @JsonKey(ignore: true)
  _$$BankAccountsListResponseImplCopyWith<_$BankAccountsListResponseImpl>
      get copyWith => throw _privateConstructorUsedError;
}

BankTransactionResponse _$BankTransactionResponseFromJson(
    Map<String, dynamic> json) {
  return _BankTransactionResponse.fromJson(json);
}

/// @nodoc
mixin _$BankTransactionResponse {
  BankTransaction get transaction => throw _privateConstructorUsedError;
  String? get message => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BankTransactionResponseCopyWith<BankTransactionResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BankTransactionResponseCopyWith<$Res> {
  factory $BankTransactionResponseCopyWith(BankTransactionResponse value,
          $Res Function(BankTransactionResponse) then) =
      _$BankTransactionResponseCopyWithImpl<$Res, BankTransactionResponse>;
  @useResult
  $Res call({BankTransaction transaction, String? message});

  $BankTransactionCopyWith<$Res> get transaction;
}

/// @nodoc
class _$BankTransactionResponseCopyWithImpl<$Res,
        $Val extends BankTransactionResponse>
    implements $BankTransactionResponseCopyWith<$Res> {
  _$BankTransactionResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? transaction = null,
    Object? message = freezed,
  }) {
    return _then(_value.copyWith(
      transaction: null == transaction
          ? _value.transaction
          : transaction // ignore: cast_nullable_to_non_nullable
              as BankTransaction,
      message: freezed == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $BankTransactionCopyWith<$Res> get transaction {
    return $BankTransactionCopyWith<$Res>(_value.transaction, (value) {
      return _then(_value.copyWith(transaction: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$BankTransactionResponseImplCopyWith<$Res>
    implements $BankTransactionResponseCopyWith<$Res> {
  factory _$$BankTransactionResponseImplCopyWith(
          _$BankTransactionResponseImpl value,
          $Res Function(_$BankTransactionResponseImpl) then) =
      __$$BankTransactionResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({BankTransaction transaction, String? message});

  @override
  $BankTransactionCopyWith<$Res> get transaction;
}

/// @nodoc
class __$$BankTransactionResponseImplCopyWithImpl<$Res>
    extends _$BankTransactionResponseCopyWithImpl<$Res,
        _$BankTransactionResponseImpl>
    implements _$$BankTransactionResponseImplCopyWith<$Res> {
  __$$BankTransactionResponseImplCopyWithImpl(
      _$BankTransactionResponseImpl _value,
      $Res Function(_$BankTransactionResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? transaction = null,
    Object? message = freezed,
  }) {
    return _then(_$BankTransactionResponseImpl(
      transaction: null == transaction
          ? _value.transaction
          : transaction // ignore: cast_nullable_to_non_nullable
              as BankTransaction,
      message: freezed == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BankTransactionResponseImpl implements _BankTransactionResponse {
  const _$BankTransactionResponseImpl(
      {required this.transaction, this.message});

  factory _$BankTransactionResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$BankTransactionResponseImplFromJson(json);

  @override
  final BankTransaction transaction;
  @override
  final String? message;

  @override
  String toString() {
    return 'BankTransactionResponse(transaction: $transaction, message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BankTransactionResponseImpl &&
            (identical(other.transaction, transaction) ||
                other.transaction == transaction) &&
            (identical(other.message, message) || other.message == message));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, transaction, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BankTransactionResponseImplCopyWith<_$BankTransactionResponseImpl>
      get copyWith => __$$BankTransactionResponseImplCopyWithImpl<
          _$BankTransactionResponseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BankTransactionResponseImplToJson(
      this,
    );
  }
}

abstract class _BankTransactionResponse implements BankTransactionResponse {
  const factory _BankTransactionResponse(
      {required final BankTransaction transaction,
      final String? message}) = _$BankTransactionResponseImpl;

  factory _BankTransactionResponse.fromJson(Map<String, dynamic> json) =
      _$BankTransactionResponseImpl.fromJson;

  @override
  BankTransaction get transaction;
  @override
  String? get message;
  @override
  @JsonKey(ignore: true)
  _$$BankTransactionResponseImplCopyWith<_$BankTransactionResponseImpl>
      get copyWith => throw _privateConstructorUsedError;
}

BankTransactionsListResponse _$BankTransactionsListResponseFromJson(
    Map<String, dynamic> json) {
  return _BankTransactionsListResponse.fromJson(json);
}

/// @nodoc
mixin _$BankTransactionsListResponse {
  List<BankTransaction> get transactions => throw _privateConstructorUsedError;
  int get limit => throw _privateConstructorUsedError;
  int get offset => throw _privateConstructorUsedError;
  int get total => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BankTransactionsListResponseCopyWith<BankTransactionsListResponse>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BankTransactionsListResponseCopyWith<$Res> {
  factory $BankTransactionsListResponseCopyWith(
          BankTransactionsListResponse value,
          $Res Function(BankTransactionsListResponse) then) =
      _$BankTransactionsListResponseCopyWithImpl<$Res,
          BankTransactionsListResponse>;
  @useResult
  $Res call(
      {List<BankTransaction> transactions, int limit, int offset, int total});
}

/// @nodoc
class _$BankTransactionsListResponseCopyWithImpl<$Res,
        $Val extends BankTransactionsListResponse>
    implements $BankTransactionsListResponseCopyWith<$Res> {
  _$BankTransactionsListResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? transactions = null,
    Object? limit = null,
    Object? offset = null,
    Object? total = null,
  }) {
    return _then(_value.copyWith(
      transactions: null == transactions
          ? _value.transactions
          : transactions // ignore: cast_nullable_to_non_nullable
              as List<BankTransaction>,
      limit: null == limit
          ? _value.limit
          : limit // ignore: cast_nullable_to_non_nullable
              as int,
      offset: null == offset
          ? _value.offset
          : offset // ignore: cast_nullable_to_non_nullable
              as int,
      total: null == total
          ? _value.total
          : total // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BankTransactionsListResponseImplCopyWith<$Res>
    implements $BankTransactionsListResponseCopyWith<$Res> {
  factory _$$BankTransactionsListResponseImplCopyWith(
          _$BankTransactionsListResponseImpl value,
          $Res Function(_$BankTransactionsListResponseImpl) then) =
      __$$BankTransactionsListResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<BankTransaction> transactions, int limit, int offset, int total});
}

/// @nodoc
class __$$BankTransactionsListResponseImplCopyWithImpl<$Res>
    extends _$BankTransactionsListResponseCopyWithImpl<$Res,
        _$BankTransactionsListResponseImpl>
    implements _$$BankTransactionsListResponseImplCopyWith<$Res> {
  __$$BankTransactionsListResponseImplCopyWithImpl(
      _$BankTransactionsListResponseImpl _value,
      $Res Function(_$BankTransactionsListResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? transactions = null,
    Object? limit = null,
    Object? offset = null,
    Object? total = null,
  }) {
    return _then(_$BankTransactionsListResponseImpl(
      transactions: null == transactions
          ? _value._transactions
          : transactions // ignore: cast_nullable_to_non_nullable
              as List<BankTransaction>,
      limit: null == limit
          ? _value.limit
          : limit // ignore: cast_nullable_to_non_nullable
              as int,
      offset: null == offset
          ? _value.offset
          : offset // ignore: cast_nullable_to_non_nullable
              as int,
      total: null == total
          ? _value.total
          : total // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BankTransactionsListResponseImpl
    implements _BankTransactionsListResponse {
  const _$BankTransactionsListResponseImpl(
      {required final List<BankTransaction> transactions,
      this.limit = 0,
      this.offset = 0,
      this.total = 0})
      : _transactions = transactions;

  factory _$BankTransactionsListResponseImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$BankTransactionsListResponseImplFromJson(json);

  final List<BankTransaction> _transactions;
  @override
  List<BankTransaction> get transactions {
    if (_transactions is EqualUnmodifiableListView) return _transactions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_transactions);
  }

  @override
  @JsonKey()
  final int limit;
  @override
  @JsonKey()
  final int offset;
  @override
  @JsonKey()
  final int total;

  @override
  String toString() {
    return 'BankTransactionsListResponse(transactions: $transactions, limit: $limit, offset: $offset, total: $total)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BankTransactionsListResponseImpl &&
            const DeepCollectionEquality()
                .equals(other._transactions, _transactions) &&
            (identical(other.limit, limit) || other.limit == limit) &&
            (identical(other.offset, offset) || other.offset == offset) &&
            (identical(other.total, total) || other.total == total));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType,
      const DeepCollectionEquality().hash(_transactions), limit, offset, total);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BankTransactionsListResponseImplCopyWith<
          _$BankTransactionsListResponseImpl>
      get copyWith => __$$BankTransactionsListResponseImplCopyWithImpl<
          _$BankTransactionsListResponseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BankTransactionsListResponseImplToJson(
      this,
    );
  }
}

abstract class _BankTransactionsListResponse
    implements BankTransactionsListResponse {
  const factory _BankTransactionsListResponse(
      {required final List<BankTransaction> transactions,
      final int limit,
      final int offset,
      final int total}) = _$BankTransactionsListResponseImpl;

  factory _BankTransactionsListResponse.fromJson(Map<String, dynamic> json) =
      _$BankTransactionsListResponseImpl.fromJson;

  @override
  List<BankTransaction> get transactions;
  @override
  int get limit;
  @override
  int get offset;
  @override
  int get total;
  @override
  @JsonKey(ignore: true)
  _$$BankTransactionsListResponseImplCopyWith<
          _$BankTransactionsListResponseImpl>
      get copyWith => throw _privateConstructorUsedError;
}

BankReconciliationResponse _$BankReconciliationResponseFromJson(
    Map<String, dynamic> json) {
  return _BankReconciliationResponse.fromJson(json);
}

/// @nodoc
mixin _$BankReconciliationResponse {
  BankReconciliation get reconciliation => throw _privateConstructorUsedError;
  String? get message => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BankReconciliationResponseCopyWith<BankReconciliationResponse>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BankReconciliationResponseCopyWith<$Res> {
  factory $BankReconciliationResponseCopyWith(BankReconciliationResponse value,
          $Res Function(BankReconciliationResponse) then) =
      _$BankReconciliationResponseCopyWithImpl<$Res,
          BankReconciliationResponse>;
  @useResult
  $Res call({BankReconciliation reconciliation, String? message});

  $BankReconciliationCopyWith<$Res> get reconciliation;
}

/// @nodoc
class _$BankReconciliationResponseCopyWithImpl<$Res,
        $Val extends BankReconciliationResponse>
    implements $BankReconciliationResponseCopyWith<$Res> {
  _$BankReconciliationResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reconciliation = null,
    Object? message = freezed,
  }) {
    return _then(_value.copyWith(
      reconciliation: null == reconciliation
          ? _value.reconciliation
          : reconciliation // ignore: cast_nullable_to_non_nullable
              as BankReconciliation,
      message: freezed == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $BankReconciliationCopyWith<$Res> get reconciliation {
    return $BankReconciliationCopyWith<$Res>(_value.reconciliation, (value) {
      return _then(_value.copyWith(reconciliation: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$BankReconciliationResponseImplCopyWith<$Res>
    implements $BankReconciliationResponseCopyWith<$Res> {
  factory _$$BankReconciliationResponseImplCopyWith(
          _$BankReconciliationResponseImpl value,
          $Res Function(_$BankReconciliationResponseImpl) then) =
      __$$BankReconciliationResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({BankReconciliation reconciliation, String? message});

  @override
  $BankReconciliationCopyWith<$Res> get reconciliation;
}

/// @nodoc
class __$$BankReconciliationResponseImplCopyWithImpl<$Res>
    extends _$BankReconciliationResponseCopyWithImpl<$Res,
        _$BankReconciliationResponseImpl>
    implements _$$BankReconciliationResponseImplCopyWith<$Res> {
  __$$BankReconciliationResponseImplCopyWithImpl(
      _$BankReconciliationResponseImpl _value,
      $Res Function(_$BankReconciliationResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reconciliation = null,
    Object? message = freezed,
  }) {
    return _then(_$BankReconciliationResponseImpl(
      reconciliation: null == reconciliation
          ? _value.reconciliation
          : reconciliation // ignore: cast_nullable_to_non_nullable
              as BankReconciliation,
      message: freezed == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BankReconciliationResponseImpl implements _BankReconciliationResponse {
  const _$BankReconciliationResponseImpl(
      {required this.reconciliation, this.message});

  factory _$BankReconciliationResponseImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$BankReconciliationResponseImplFromJson(json);

  @override
  final BankReconciliation reconciliation;
  @override
  final String? message;

  @override
  String toString() {
    return 'BankReconciliationResponse(reconciliation: $reconciliation, message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BankReconciliationResponseImpl &&
            (identical(other.reconciliation, reconciliation) ||
                other.reconciliation == reconciliation) &&
            (identical(other.message, message) || other.message == message));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, reconciliation, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BankReconciliationResponseImplCopyWith<_$BankReconciliationResponseImpl>
      get copyWith => __$$BankReconciliationResponseImplCopyWithImpl<
          _$BankReconciliationResponseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BankReconciliationResponseImplToJson(
      this,
    );
  }
}

abstract class _BankReconciliationResponse
    implements BankReconciliationResponse {
  const factory _BankReconciliationResponse(
      {required final BankReconciliation reconciliation,
      final String? message}) = _$BankReconciliationResponseImpl;

  factory _BankReconciliationResponse.fromJson(Map<String, dynamic> json) =
      _$BankReconciliationResponseImpl.fromJson;

  @override
  BankReconciliation get reconciliation;
  @override
  String? get message;
  @override
  @JsonKey(ignore: true)
  _$$BankReconciliationResponseImplCopyWith<_$BankReconciliationResponseImpl>
      get copyWith => throw _privateConstructorUsedError;
}

BankReconciliationsListResponse _$BankReconciliationsListResponseFromJson(
    Map<String, dynamic> json) {
  return _BankReconciliationsListResponse.fromJson(json);
}

/// @nodoc
mixin _$BankReconciliationsListResponse {
  List<BankReconciliation> get reconciliations =>
      throw _privateConstructorUsedError;
  int get count => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BankReconciliationsListResponseCopyWith<BankReconciliationsListResponse>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BankReconciliationsListResponseCopyWith<$Res> {
  factory $BankReconciliationsListResponseCopyWith(
          BankReconciliationsListResponse value,
          $Res Function(BankReconciliationsListResponse) then) =
      _$BankReconciliationsListResponseCopyWithImpl<$Res,
          BankReconciliationsListResponse>;
  @useResult
  $Res call({List<BankReconciliation> reconciliations, int count});
}

/// @nodoc
class _$BankReconciliationsListResponseCopyWithImpl<$Res,
        $Val extends BankReconciliationsListResponse>
    implements $BankReconciliationsListResponseCopyWith<$Res> {
  _$BankReconciliationsListResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reconciliations = null,
    Object? count = null,
  }) {
    return _then(_value.copyWith(
      reconciliations: null == reconciliations
          ? _value.reconciliations
          : reconciliations // ignore: cast_nullable_to_non_nullable
              as List<BankReconciliation>,
      count: null == count
          ? _value.count
          : count // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BankReconciliationsListResponseImplCopyWith<$Res>
    implements $BankReconciliationsListResponseCopyWith<$Res> {
  factory _$$BankReconciliationsListResponseImplCopyWith(
          _$BankReconciliationsListResponseImpl value,
          $Res Function(_$BankReconciliationsListResponseImpl) then) =
      __$$BankReconciliationsListResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<BankReconciliation> reconciliations, int count});
}

/// @nodoc
class __$$BankReconciliationsListResponseImplCopyWithImpl<$Res>
    extends _$BankReconciliationsListResponseCopyWithImpl<$Res,
        _$BankReconciliationsListResponseImpl>
    implements _$$BankReconciliationsListResponseImplCopyWith<$Res> {
  __$$BankReconciliationsListResponseImplCopyWithImpl(
      _$BankReconciliationsListResponseImpl _value,
      $Res Function(_$BankReconciliationsListResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reconciliations = null,
    Object? count = null,
  }) {
    return _then(_$BankReconciliationsListResponseImpl(
      reconciliations: null == reconciliations
          ? _value._reconciliations
          : reconciliations // ignore: cast_nullable_to_non_nullable
              as List<BankReconciliation>,
      count: null == count
          ? _value.count
          : count // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BankReconciliationsListResponseImpl
    implements _BankReconciliationsListResponse {
  const _$BankReconciliationsListResponseImpl(
      {final List<BankReconciliation> reconciliations = const [],
      this.count = 0})
      : _reconciliations = reconciliations;

  factory _$BankReconciliationsListResponseImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$BankReconciliationsListResponseImplFromJson(json);

  final List<BankReconciliation> _reconciliations;
  @override
  @JsonKey()
  List<BankReconciliation> get reconciliations {
    if (_reconciliations is EqualUnmodifiableListView) return _reconciliations;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_reconciliations);
  }

  @override
  @JsonKey()
  final int count;

  @override
  String toString() {
    return 'BankReconciliationsListResponse(reconciliations: $reconciliations, count: $count)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BankReconciliationsListResponseImpl &&
            const DeepCollectionEquality()
                .equals(other._reconciliations, _reconciliations) &&
            (identical(other.count, count) || other.count == count));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType,
      const DeepCollectionEquality().hash(_reconciliations), count);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BankReconciliationsListResponseImplCopyWith<
          _$BankReconciliationsListResponseImpl>
      get copyWith => __$$BankReconciliationsListResponseImplCopyWithImpl<
          _$BankReconciliationsListResponseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BankReconciliationsListResponseImplToJson(
      this,
    );
  }
}

abstract class _BankReconciliationsListResponse
    implements BankReconciliationsListResponse {
  const factory _BankReconciliationsListResponse(
      {final List<BankReconciliation> reconciliations,
      final int count}) = _$BankReconciliationsListResponseImpl;

  factory _BankReconciliationsListResponse.fromJson(Map<String, dynamic> json) =
      _$BankReconciliationsListResponseImpl.fromJson;

  @override
  List<BankReconciliation> get reconciliations;
  @override
  int get count;
  @override
  @JsonKey(ignore: true)
  _$$BankReconciliationsListResponseImplCopyWith<
          _$BankReconciliationsListResponseImpl>
      get copyWith => throw _privateConstructorUsedError;
}

BankAccountSummaryResponse _$BankAccountSummaryResponseFromJson(
    Map<String, dynamic> json) {
  return _BankAccountSummaryResponse.fromJson(json);
}

/// @nodoc
mixin _$BankAccountSummaryResponse {
  TenantBankAccount? get account =>
      throw _privateConstructorUsedError; // Made nullable for default responses when endpoint doesn't exist
  @JsonKey(name: 'total_deposits_this_month')
  double get totalDepositsThisMonth => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_withdrawals_this_month')
  double get totalWithdrawalsThisMonth => throw _privateConstructorUsedError;
  @JsonKey(name: 'transaction_count')
  int get transactionCount => throw _privateConstructorUsedError;
  @JsonKey(name: 'od_utilization_percent')
  double get odUtilizationPercent => throw _privateConstructorUsedError;
  @JsonKey(name: 'last_reconciliation_date')
  DateTime? get lastReconciliationDate => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BankAccountSummaryResponseCopyWith<BankAccountSummaryResponse>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BankAccountSummaryResponseCopyWith<$Res> {
  factory $BankAccountSummaryResponseCopyWith(BankAccountSummaryResponse value,
          $Res Function(BankAccountSummaryResponse) then) =
      _$BankAccountSummaryResponseCopyWithImpl<$Res,
          BankAccountSummaryResponse>;
  @useResult
  $Res call(
      {TenantBankAccount? account,
      @JsonKey(name: 'total_deposits_this_month') double totalDepositsThisMonth,
      @JsonKey(name: 'total_withdrawals_this_month')
      double totalWithdrawalsThisMonth,
      @JsonKey(name: 'transaction_count') int transactionCount,
      @JsonKey(name: 'od_utilization_percent') double odUtilizationPercent,
      @JsonKey(name: 'last_reconciliation_date')
      DateTime? lastReconciliationDate});

  $TenantBankAccountCopyWith<$Res>? get account;
}

/// @nodoc
class _$BankAccountSummaryResponseCopyWithImpl<$Res,
        $Val extends BankAccountSummaryResponse>
    implements $BankAccountSummaryResponseCopyWith<$Res> {
  _$BankAccountSummaryResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? account = freezed,
    Object? totalDepositsThisMonth = null,
    Object? totalWithdrawalsThisMonth = null,
    Object? transactionCount = null,
    Object? odUtilizationPercent = null,
    Object? lastReconciliationDate = freezed,
  }) {
    return _then(_value.copyWith(
      account: freezed == account
          ? _value.account
          : account // ignore: cast_nullable_to_non_nullable
              as TenantBankAccount?,
      totalDepositsThisMonth: null == totalDepositsThisMonth
          ? _value.totalDepositsThisMonth
          : totalDepositsThisMonth // ignore: cast_nullable_to_non_nullable
              as double,
      totalWithdrawalsThisMonth: null == totalWithdrawalsThisMonth
          ? _value.totalWithdrawalsThisMonth
          : totalWithdrawalsThisMonth // ignore: cast_nullable_to_non_nullable
              as double,
      transactionCount: null == transactionCount
          ? _value.transactionCount
          : transactionCount // ignore: cast_nullable_to_non_nullable
              as int,
      odUtilizationPercent: null == odUtilizationPercent
          ? _value.odUtilizationPercent
          : odUtilizationPercent // ignore: cast_nullable_to_non_nullable
              as double,
      lastReconciliationDate: freezed == lastReconciliationDate
          ? _value.lastReconciliationDate
          : lastReconciliationDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $TenantBankAccountCopyWith<$Res>? get account {
    if (_value.account == null) {
      return null;
    }

    return $TenantBankAccountCopyWith<$Res>(_value.account!, (value) {
      return _then(_value.copyWith(account: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$BankAccountSummaryResponseImplCopyWith<$Res>
    implements $BankAccountSummaryResponseCopyWith<$Res> {
  factory _$$BankAccountSummaryResponseImplCopyWith(
          _$BankAccountSummaryResponseImpl value,
          $Res Function(_$BankAccountSummaryResponseImpl) then) =
      __$$BankAccountSummaryResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {TenantBankAccount? account,
      @JsonKey(name: 'total_deposits_this_month') double totalDepositsThisMonth,
      @JsonKey(name: 'total_withdrawals_this_month')
      double totalWithdrawalsThisMonth,
      @JsonKey(name: 'transaction_count') int transactionCount,
      @JsonKey(name: 'od_utilization_percent') double odUtilizationPercent,
      @JsonKey(name: 'last_reconciliation_date')
      DateTime? lastReconciliationDate});

  @override
  $TenantBankAccountCopyWith<$Res>? get account;
}

/// @nodoc
class __$$BankAccountSummaryResponseImplCopyWithImpl<$Res>
    extends _$BankAccountSummaryResponseCopyWithImpl<$Res,
        _$BankAccountSummaryResponseImpl>
    implements _$$BankAccountSummaryResponseImplCopyWith<$Res> {
  __$$BankAccountSummaryResponseImplCopyWithImpl(
      _$BankAccountSummaryResponseImpl _value,
      $Res Function(_$BankAccountSummaryResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? account = freezed,
    Object? totalDepositsThisMonth = null,
    Object? totalWithdrawalsThisMonth = null,
    Object? transactionCount = null,
    Object? odUtilizationPercent = null,
    Object? lastReconciliationDate = freezed,
  }) {
    return _then(_$BankAccountSummaryResponseImpl(
      account: freezed == account
          ? _value.account
          : account // ignore: cast_nullable_to_non_nullable
              as TenantBankAccount?,
      totalDepositsThisMonth: null == totalDepositsThisMonth
          ? _value.totalDepositsThisMonth
          : totalDepositsThisMonth // ignore: cast_nullable_to_non_nullable
              as double,
      totalWithdrawalsThisMonth: null == totalWithdrawalsThisMonth
          ? _value.totalWithdrawalsThisMonth
          : totalWithdrawalsThisMonth // ignore: cast_nullable_to_non_nullable
              as double,
      transactionCount: null == transactionCount
          ? _value.transactionCount
          : transactionCount // ignore: cast_nullable_to_non_nullable
              as int,
      odUtilizationPercent: null == odUtilizationPercent
          ? _value.odUtilizationPercent
          : odUtilizationPercent // ignore: cast_nullable_to_non_nullable
              as double,
      lastReconciliationDate: freezed == lastReconciliationDate
          ? _value.lastReconciliationDate
          : lastReconciliationDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BankAccountSummaryResponseImpl implements _BankAccountSummaryResponse {
  const _$BankAccountSummaryResponseImpl(
      {this.account,
      @JsonKey(name: 'total_deposits_this_month')
      this.totalDepositsThisMonth = 0.0,
      @JsonKey(name: 'total_withdrawals_this_month')
      this.totalWithdrawalsThisMonth = 0.0,
      @JsonKey(name: 'transaction_count') this.transactionCount = 0,
      @JsonKey(name: 'od_utilization_percent') this.odUtilizationPercent = 0.0,
      @JsonKey(name: 'last_reconciliation_date') this.lastReconciliationDate});

  factory _$BankAccountSummaryResponseImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$BankAccountSummaryResponseImplFromJson(json);

  @override
  final TenantBankAccount? account;
// Made nullable for default responses when endpoint doesn't exist
  @override
  @JsonKey(name: 'total_deposits_this_month')
  final double totalDepositsThisMonth;
  @override
  @JsonKey(name: 'total_withdrawals_this_month')
  final double totalWithdrawalsThisMonth;
  @override
  @JsonKey(name: 'transaction_count')
  final int transactionCount;
  @override
  @JsonKey(name: 'od_utilization_percent')
  final double odUtilizationPercent;
  @override
  @JsonKey(name: 'last_reconciliation_date')
  final DateTime? lastReconciliationDate;

  @override
  String toString() {
    return 'BankAccountSummaryResponse(account: $account, totalDepositsThisMonth: $totalDepositsThisMonth, totalWithdrawalsThisMonth: $totalWithdrawalsThisMonth, transactionCount: $transactionCount, odUtilizationPercent: $odUtilizationPercent, lastReconciliationDate: $lastReconciliationDate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BankAccountSummaryResponseImpl &&
            (identical(other.account, account) || other.account == account) &&
            (identical(other.totalDepositsThisMonth, totalDepositsThisMonth) ||
                other.totalDepositsThisMonth == totalDepositsThisMonth) &&
            (identical(other.totalWithdrawalsThisMonth,
                    totalWithdrawalsThisMonth) ||
                other.totalWithdrawalsThisMonth == totalWithdrawalsThisMonth) &&
            (identical(other.transactionCount, transactionCount) ||
                other.transactionCount == transactionCount) &&
            (identical(other.odUtilizationPercent, odUtilizationPercent) ||
                other.odUtilizationPercent == odUtilizationPercent) &&
            (identical(other.lastReconciliationDate, lastReconciliationDate) ||
                other.lastReconciliationDate == lastReconciliationDate));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      account,
      totalDepositsThisMonth,
      totalWithdrawalsThisMonth,
      transactionCount,
      odUtilizationPercent,
      lastReconciliationDate);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BankAccountSummaryResponseImplCopyWith<_$BankAccountSummaryResponseImpl>
      get copyWith => __$$BankAccountSummaryResponseImplCopyWithImpl<
          _$BankAccountSummaryResponseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BankAccountSummaryResponseImplToJson(
      this,
    );
  }
}

abstract class _BankAccountSummaryResponse
    implements BankAccountSummaryResponse {
  const factory _BankAccountSummaryResponse(
          {final TenantBankAccount? account,
          @JsonKey(name: 'total_deposits_this_month')
          final double totalDepositsThisMonth,
          @JsonKey(name: 'total_withdrawals_this_month')
          final double totalWithdrawalsThisMonth,
          @JsonKey(name: 'transaction_count') final int transactionCount,
          @JsonKey(name: 'od_utilization_percent')
          final double odUtilizationPercent,
          @JsonKey(name: 'last_reconciliation_date')
          final DateTime? lastReconciliationDate}) =
      _$BankAccountSummaryResponseImpl;

  factory _BankAccountSummaryResponse.fromJson(Map<String, dynamic> json) =
      _$BankAccountSummaryResponseImpl.fromJson;

  @override
  TenantBankAccount? get account;
  @override // Made nullable for default responses when endpoint doesn't exist
  @JsonKey(name: 'total_deposits_this_month')
  double get totalDepositsThisMonth;
  @override
  @JsonKey(name: 'total_withdrawals_this_month')
  double get totalWithdrawalsThisMonth;
  @override
  @JsonKey(name: 'transaction_count')
  int get transactionCount;
  @override
  @JsonKey(name: 'od_utilization_percent')
  double get odUtilizationPercent;
  @override
  @JsonKey(name: 'last_reconciliation_date')
  DateTime? get lastReconciliationDate;
  @override
  @JsonKey(ignore: true)
  _$$BankAccountSummaryResponseImplCopyWith<_$BankAccountSummaryResponseImpl>
      get copyWith => throw _privateConstructorUsedError;
}

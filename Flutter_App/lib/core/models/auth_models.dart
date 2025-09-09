import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_models.freezed.dart';
part 'auth_models.g.dart';

/// Login request model
@freezed
class LoginRequest with _$LoginRequest {
  const factory LoginRequest({
    required String email,
    required String password,
    @Default(false) bool rememberMe,
    String? deviceId,
    String? deviceName,
    String? fcmToken,
    Map<String, dynamic>? deviceInfo,
  }) = _LoginRequest;

  factory LoginRequest.fromJson(Map<String, dynamic> json) => _$LoginRequestFromJson(json);
}

/// Login response model
@freezed
class LoginResponse with _$LoginResponse {
  const factory LoginResponse({
    required String accessToken,
    required String refreshToken,
    required String tokenType,
    required int expiresIn,
    required Map<String, dynamic> user,
    String? message,
    Map<String, dynamic>? permissions,
    Map<String, dynamic>? preferences,
  }) = _LoginResponse;

  factory LoginResponse.fromJson(Map<String, dynamic> json) => _$LoginResponseFromJson(json);
}

/// Registration request model
@freezed
class RegisterRequest with _$RegisterRequest {
  const factory RegisterRequest({
    required String email,
    required String password,
    required String passwordConfirmation,
    required String firstName,
    required String lastName,
    String? phoneNumber,
    String? businessName,
    String? businessType,
    String? businessAddress,
    String? timezone,
    String? language,
    String? currency,
    String? referralCode,
    @Default(false) bool acceptTerms,
    @Default(false) bool acceptPrivacyPolicy,
    @Default(false) bool acceptMarketing,
    Map<String, dynamic>? deviceInfo,
  }) = _RegisterRequest;

  factory RegisterRequest.fromJson(Map<String, dynamic> json) => _$RegisterRequestFromJson(json);
}

/// Registration response model
@freezed
class RegisterResponse with _$RegisterResponse {
  const factory RegisterResponse({
    required String message,
    String? userId,
    String? verificationToken,
    Map<String, dynamic>? user,
  }) = _RegisterResponse;

  factory RegisterResponse.fromJson(Map<String, dynamic> json) => _$RegisterResponseFromJson(json);
}

/// Password reset request model
@freezed
class PasswordResetRequest with _$PasswordResetRequest {
  const factory PasswordResetRequest({
    required String email,
    String? returnUrl,
  }) = _PasswordResetRequest;

  factory PasswordResetRequest.fromJson(Map<String, dynamic> json) => _$PasswordResetRequestFromJson(json);
}

/// Password reset response model
@freezed
class PasswordResetResponse with _$PasswordResetResponse {
  const factory PasswordResetResponse({
    required String message,
    String? resetToken,
  }) = _PasswordResetResponse;

  factory PasswordResetResponse.fromJson(Map<String, dynamic> json) => _$PasswordResetResponseFromJson(json);
}

/// Password update request model
@freezed
class PasswordUpdateRequest with _$PasswordUpdateRequest {
  const factory PasswordUpdateRequest({
    required String token,
    required String password,
    required String passwordConfirmation,
  }) = _PasswordUpdateRequest;

  factory PasswordUpdateRequest.fromJson(Map<String, dynamic> json) => _$PasswordUpdateRequestFromJson(json);
}

/// Email verification request model
@freezed
class EmailVerificationRequest with _$EmailVerificationRequest {
  const factory EmailVerificationRequest({
    required String token,
    String? userId,
  }) = _EmailVerificationRequest;

  factory EmailVerificationRequest.fromJson(Map<String, dynamic> json) => _$EmailVerificationRequestFromJson(json);
}

/// Refresh token request model
@freezed
class RefreshTokenRequest with _$RefreshTokenRequest {
  const factory RefreshTokenRequest({
    required String refreshToken,
    String? deviceId,
    Map<String, dynamic>? deviceInfo,
  }) = _RefreshTokenRequest;

  factory RefreshTokenRequest.fromJson(Map<String, dynamic> json) => _$RefreshTokenRequestFromJson(json);
}

/// Refresh token response model
@freezed
class RefreshTokenResponse with _$RefreshTokenResponse {
  const factory RefreshTokenResponse({
    required String accessToken,
    required String refreshToken,
    required String tokenType,
    required int expiresIn,
  }) = _RefreshTokenResponse;

  factory RefreshTokenResponse.fromJson(Map<String, dynamic> json) => _$RefreshTokenResponseFromJson(json);
}

/// Two-factor authentication setup request
@freezed
class TwoFactorSetupRequest with _$TwoFactorSetupRequest {
  const factory TwoFactorSetupRequest({
    required String password,
    required TwoFactorMethod method,
    String? phoneNumber,
  }) = _TwoFactorSetupRequest;

  factory TwoFactorSetupRequest.fromJson(Map<String, dynamic> json) => _$TwoFactorSetupRequestFromJson(json);
}

/// Two-factor authentication setup response
@freezed
class TwoFactorSetupResponse with _$TwoFactorSetupResponse {
  const factory TwoFactorSetupResponse({
    required String secret,
    required String qrCode,
    required List<String> backupCodes,
    String? message,
  }) = _TwoFactorSetupResponse;

  factory TwoFactorSetupResponse.fromJson(Map<String, dynamic> json) => _$TwoFactorSetupResponseFromJson(json);
}

/// Two-factor authentication verification request
@freezed
class TwoFactorVerificationRequest with _$TwoFactorVerificationRequest {
  const factory TwoFactorVerificationRequest({
    required String code,
    required TwoFactorMethod method,
    @Default(false) bool trustDevice,
  }) = _TwoFactorVerificationRequest;

  factory TwoFactorVerificationRequest.fromJson(Map<String, dynamic> json) => _$TwoFactorVerificationRequestFromJson(json);
}

/// Biometric authentication setup request
@freezed
class BiometricSetupRequest with _$BiometricSetupRequest {
  const factory BiometricSetupRequest({
    required String password,
    required String publicKey,
    required BiometricType biometricType,
    String? deviceId,
    String? deviceName,
  }) = _BiometricSetupRequest;

  factory BiometricSetupRequest.fromJson(Map<String, dynamic> json) => _$BiometricSetupRequestFromJson(json);
}

/// Biometric authentication request
@freezed
class BiometricAuthRequest with _$BiometricAuthRequest {
  const factory BiometricAuthRequest({
    required String challenge,
    required String signature,
    required BiometricType biometricType,
    String? deviceId,
  }) = _BiometricAuthRequest;

  factory BiometricAuthRequest.fromJson(Map<String, dynamic> json) => _$BiometricAuthRequestFromJson(json);
}

/// Social authentication request
@freezed
class SocialAuthRequest with _$SocialAuthRequest {
  const factory SocialAuthRequest({
    required String provider,
    required String token,
    String? email,
    String? firstName,
    String? lastName,
    String? avatar,
    Map<String, dynamic>? deviceInfo,
  }) = _SocialAuthRequest;

  factory SocialAuthRequest.fromJson(Map<String, dynamic> json) => _$SocialAuthRequestFromJson(json);
}

/// Account verification request
@freezed
class AccountVerificationRequest with _$AccountVerificationRequest {
  const factory AccountVerificationRequest({
    required String token,
    required VerificationType type,
  }) = _AccountVerificationRequest;

  factory AccountVerificationRequest.fromJson(Map<String, dynamic> json) => _$AccountVerificationRequestFromJson(json);
}

/// Session information model
@freezed
class SessionInfo with _$SessionInfo {
  const factory SessionInfo({
    required String id,
    required String userId,
    required String deviceId,
    required String deviceName,
    required String ipAddress,
    required String userAgent,
    required DateTime createdAt,
    required DateTime lastActiveAt,
    DateTime? expiresAt,
    @Default(true) bool isActive,
    @Default(false) bool isCurrent,
    String? location,
    Map<String, dynamic>? metadata,
  }) = _SessionInfo;

  factory SessionInfo.fromJson(Map<String, dynamic> json) => _$SessionInfoFromJson(json);
}

/// Authentication token model
@freezed
class AuthToken with _$AuthToken {
  const factory AuthToken({
    required String accessToken,
    required String refreshToken,
    required String tokenType,
    required DateTime issuedAt,
    required DateTime expiresAt,
    String? scope,
    Map<String, dynamic>? claims,
  }) = _AuthToken;

  factory AuthToken.fromJson(Map<String, dynamic> json) => _$AuthTokenFromJson(json);
}

/// Authentication context model
@freezed
class AuthContext with _$AuthContext {
  const factory AuthContext({
    required String userId,
    required String sessionId,
    required List<String> permissions,
    required Map<String, dynamic> preferences,
    String? tenantId,
    String? organizationId,
    DateTime? lastPasswordChange,
    @Default(false) bool requiresPasswordChange,
    @Default(false) bool requiresTwoFactor,
    @Default(false) bool hasBiometricEnabled,
    List<String>? trustedDevices,
    Map<String, dynamic>? securitySettings,
  }) = _AuthContext;

  factory AuthContext.fromJson(Map<String, dynamic> json) => _$AuthContextFromJson(json);
}

/// Authentication method enumeration
enum AuthMethod {
  @JsonValue('email_password')
  emailPassword,
  
  @JsonValue('biometric')
  biometric,
  
  @JsonValue('two_factor')
  twoFactor,
  
  @JsonValue('social_google')
  socialGoogle,
  
  @JsonValue('social_apple')
  socialApple,
  
  @JsonValue('social_facebook')
  socialFacebook,
  
  @JsonValue('magic_link')
  magicLink,
  
  @JsonValue('sso')
  sso,
}

/// Two-factor authentication method enumeration
enum TwoFactorMethod {
  @JsonValue('totp')
  totp, // Time-based One-Time Password (Google Authenticator)
  
  @JsonValue('sms')
  sms,
  
  @JsonValue('email')
  email,
  
  @JsonValue('backup_code')
  backupCode,
}

/// Biometric authentication type enumeration
enum BiometricType {
  @JsonValue('fingerprint')
  fingerprint,
  
  @JsonValue('face_id')
  faceId,
  
  @JsonValue('iris')
  iris,
  
  @JsonValue('voice')
  voice,
}

/// Verification type enumeration
enum VerificationType {
  @JsonValue('email')
  email,
  
  @JsonValue('phone')
  phone,
  
  @JsonValue('password_reset')
  passwordReset,
  
  @JsonValue('account_activation')
  accountActivation,
}

/// Social authentication provider enumeration
enum SocialProvider {
  @JsonValue('google')
  google,
  
  @JsonValue('apple')
  apple,
  
  @JsonValue('facebook')
  facebook,
  
  @JsonValue('twitter')
  twitter,
  
  @JsonValue('linkedin')
  linkedin,
  
  @JsonValue('github')
  github,
}

/// Authentication error enumeration
enum AuthErrorType {
  invalidCredentials,
  accountLocked,
  accountDisabled,
  accountNotVerified,
  tokenExpired,
  tokenInvalid,
  passwordExpired,
  twoFactorRequired,
  biometricNotAvailable,
  biometricNotEnrolled,
  biometricAuthFailed,
  networkError,
  serverError,
  rateLimitExceeded,
  unknownError,
}

/// Extensions for authentication models
extension LoginRequestExtensions on LoginRequest {
  /// Validate login request
  List<String> validate() {
    final errors = <String>[];
    
    if (email.isEmpty) {
      errors.add('Email is required');
    } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      errors.add('Please enter a valid email address');
    }
    
    if (password.isEmpty) {
      errors.add('Password is required');
    } else if (password.length < 8) {
      errors.add('Password must be at least 8 characters long');
    }
    
    return errors;
  }
}

extension RegisterRequestExtensions on RegisterRequest {
  /// Validate registration request
  List<String> validate() {
    final errors = <String>[];
    
    if (email.isEmpty) {
      errors.add('Email is required');
    } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      errors.add('Please enter a valid email address');
    }
    
    if (firstName.isEmpty) {
      errors.add('First name is required');
    }
    
    if (lastName.isEmpty) {
      errors.add('Last name is required');
    }
    
    if (password.isEmpty) {
      errors.add('Password is required');
    } else if (password.length < 8) {
      errors.add('Password must be at least 8 characters long');
    } else if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(password)) {
      errors.add('Password must contain at least one uppercase letter, one lowercase letter, and one number');
    }
    
    if (password != passwordConfirmation) {
      errors.add('Passwords do not match');
    }
    
    if (phoneNumber != null && phoneNumber!.isNotEmpty) {
      if (!RegExp(r'^\+?[1-9]\d{1,14}$').hasMatch(phoneNumber!)) {
        errors.add('Please enter a valid phone number');
      }
    }
    
    if (!acceptTerms) {
      errors.add('You must accept the Terms of Service');
    }
    
    if (!acceptPrivacyPolicy) {
      errors.add('You must accept the Privacy Policy');
    }
    
    return errors;
  }
}

extension AuthTokenExtensions on AuthToken {
  /// Check if token is expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  
  /// Check if token expires soon (within 5 minutes)
  bool get expiresSoon => DateTime.now().add(const Duration(minutes: 5)).isAfter(expiresAt);
  
  /// Get time until expiration
  Duration get timeUntilExpiration => expiresAt.difference(DateTime.now());
  
  /// Get remaining validity percentage
  double get validityPercentage {
    final total = expiresAt.difference(issuedAt);
    final remaining = timeUntilExpiration;
    
    if (remaining.isNegative) return 0.0;
    return remaining.inMilliseconds / total.inMilliseconds;
  }
}

extension SessionInfoExtensions on SessionInfo {
  /// Get time since last active
  Duration get timeSinceLastActive => DateTime.now().difference(lastActiveAt);
  
  /// Check if session is active (last active within 30 minutes)
  bool get isRecentlyActive => timeSinceLastActive.inMinutes <= 30;
  
  /// Get session duration
  Duration get sessionDuration => lastActiveAt.difference(createdAt);
  
  /// Check if session is expired
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

extension AuthContextExtensions on AuthContext {
  /// Check if user has specific permission
  bool hasPermission(String permission) => permissions.contains(permission);
  
  /// Check if user has any of the given permissions
  bool hasAnyPermission(List<String> permissionList) => 
      permissionList.any((permission) => permissions.contains(permission));
  
  /// Check if user has all of the given permissions
  bool hasAllPermissions(List<String> permissionList) =>
      permissionList.every((permission) => permissions.contains(permission));
  
  /// Check if password needs to be changed
  bool get needsPasswordChange {
    if (requiresPasswordChange) return true;
    if (lastPasswordChange == null) return false;
    
    // Require password change if older than 90 days
    final daysSinceChange = DateTime.now().difference(lastPasswordChange!).inDays;
    return daysSinceChange > 90;
  }
}
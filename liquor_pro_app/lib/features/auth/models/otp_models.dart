/// OTP-related models matching backend structure exactly
library;

// ==================== CHECK USER ====================

/// Check User Request
class CheckUserRequest {
  final String mobile;

  CheckUserRequest({required this.mobile});

  Map<String, dynamic> toJson() {
    return {'mobile': mobile};
  }
}

/// Check User Response
/// Backend sends OTP during check-user and returns session info.
/// Security: `exists` is always false — the backend never reveals
/// whether the phone number is registered. Login vs registration
/// is determined only after OTP verification (verify-otp response).
class CheckUserResponse {
  final String message;
  final String? sessionId;
  final DateTime? otpSentAt;
  final DateTime? expiresAt;

  CheckUserResponse({
    required this.message,
    this.sessionId,
    this.otpSentAt,
    this.expiresAt,
  });

  factory CheckUserResponse.fromJson(Map<String, dynamic> json) {
    return CheckUserResponse(
      message: json['message'] as String? ?? '',
      sessionId: json['session_id'] as String?,
      otpSentAt: json['otp_sent_at'] != null
          ? DateTime.tryParse(json['otp_sent_at'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
    );
  }

  /// Whether OTP session info is available (phone-based check)
  bool get hasOtpSession => sessionId != null && sessionId!.isNotEmpty;
}

// ==================== SEND OTP ====================

/// Send OTP Request (for existing user login)
class SendOtpRequest {
  final String mobile;

  SendOtpRequest({required this.mobile});

  Map<String, dynamic> toJson() {
    return {'mobile': mobile};
  }
}

/// Send OTP for Registration Request
class SendOtpForRegistrationRequest {
  final String phone;
  final String email;
  final String firstName;

  SendOtpForRegistrationRequest({
    required this.phone,
    required this.email,
    required this.firstName,
  });

  Map<String, dynamic> toJson() {
    return {
      'phone': phone,
      'email': email,
      'first_name': firstName,
    };
  }
}

/// Send OTP Response
class SendOtpResponse {
  final String message;
  final DateTime otpSentAt;
  final DateTime expiresAt;
  final String sessionId;

  SendOtpResponse({
    required this.message,
    required this.otpSentAt,
    required this.expiresAt,
    required this.sessionId,
  });

  factory SendOtpResponse.fromJson(Map<String, dynamic> json) {
    return SendOtpResponse(
      message: json['message'] as String,
      otpSentAt: DateTime.parse(json['otp_sent_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      sessionId: json['session_id'] as String,
    );
  }
}

// ==================== VERIFY OTP ====================

/// Verify OTP Request
class VerifyOtpRequest {
  final String mobile;
  final String otp;
  final String? sessionId;

  VerifyOtpRequest({
    required this.mobile,
    required this.otp,
    this.sessionId,
  });

  Map<String, dynamic> toJson() {
    return {
      'mobile': mobile,
      'otp': otp,
      if (sessionId != null) 'session_id': sessionId,
    };
  }
}

/// Verify OTP Response (can be login or registration continuation)
class VerifyOtpResponse {
  final String? token;
  final String? refreshToken;
  final DateTime? expiresAt;
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? tenant;
  final String? message;
  final String? purpose; // "login" or "registration"
  final String? sessionId; // Device session ID for device management
  final String? registrationToken; // Single-use token for completing registration

  VerifyOtpResponse({
    this.token,
    this.refreshToken,
    this.expiresAt,
    this.user,
    this.tenant,
    this.message,
    this.purpose,
    this.sessionId,
    this.registrationToken,
  });

  factory VerifyOtpResponse.fromJson(Map<String, dynamic> json) {
    return VerifyOtpResponse(
      token: json['token'] as String?,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      user: json['user'] as Map<String, dynamic>?,
      tenant: json['tenant'] as Map<String, dynamic>?,
      message: json['message'] as String?,
      purpose: json['purpose'] as String?,
      sessionId: json['session_id'] as String?,
      registrationToken: json['registration_token'] as String?,
    );
  }

  bool get isLogin => token != null && user != null;
  bool get needsRegistration => purpose == 'registration' && token == null;
}

// ==================== REGISTRATION ====================

/// Registration Request
class RegistrationRequest {
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String phone;
  final String tenantName; // Subdomain/slug
  final String companyName;
  final String registrationToken; // Single-use token from OTP verification

  RegistrationRequest({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.tenantName,
    required this.companyName,
    required this.registrationToken,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'tenant_name': tenantName,
      'company_name': companyName,
      'registration_token': registrationToken,
    };
  }
}

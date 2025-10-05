/// OTP-related models matching backend structure exactly

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
class CheckUserResponse {
  final bool exists;
  final String message;

  CheckUserResponse({
    required this.exists,
    required this.message,
  });

  factory CheckUserResponse.fromJson(Map<String, dynamic> json) {
    return CheckUserResponse(
      exists: json['exists'] as bool,
      message: json['message'] as String,
    );
  }
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
  final String purpose; // "login" or "registration"

  SendOtpResponse({
    required this.message,
    required this.otpSentAt,
    required this.expiresAt,
    required this.sessionId,
    required this.purpose,
  });

  factory SendOtpResponse.fromJson(Map<String, dynamic> json) {
    return SendOtpResponse(
      message: json['message'] as String,
      otpSentAt: DateTime.parse(json['otp_sent_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      sessionId: json['session_id'] as String,
      purpose: json['purpose'] as String,
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

  VerifyOtpResponse({
    this.token,
    this.refreshToken,
    this.expiresAt,
    this.user,
    this.tenant,
    this.message,
    this.purpose,
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

  RegistrationRequest({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.tenantName,
    required this.companyName,
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
    };
  }
}

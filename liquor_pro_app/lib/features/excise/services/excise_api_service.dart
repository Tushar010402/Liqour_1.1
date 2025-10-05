import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/excise_models.dart';

class ExciseApiService {
  final String baseUrl;
  final Future<String?> Function() getToken;

  ExciseApiService({
    required this.baseUrl,
    required this.getToken,
  });

  Future<Map<String, String>> get _headers async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${token ?? ''}',
    };
  }

  // ==================== LICENSE MANAGEMENT ====================

  /// Get all licenses for the tenant
  Future<List<ExciseLicense>> getLicenses() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/excise/licenses'),
      headers: await _headers,
    );

    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((json) => ExciseLicense.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load licenses: ${response.body}');
    }
  }

  /// Get license by ID
  Future<ExciseLicense> getLicenseById(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/excise/licenses/$id'),
      headers: await _headers,
    );

    if (response.statusCode == 200) {
      return ExciseLicense.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load license: ${response.body}');
    }
  }

  /// Create new license
  Future<ExciseLicense> createLicense({
    required String shopId,
    required String licenseNumber,
    required LicenseType licenseType,
    required DateTime issueDate,
    required DateTime expiryDate,
    required String issuingAuthority,
    required double monthlyFee,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/excise/licenses'),
      headers: await _headers,
      body: json.encode({
        'shop_id': shopId,
        'license_number': licenseNumber,
        'license_type': licenseType.value,
        'issue_date': issueDate.toIso8601String(),
        'expiry_date': expiryDate.toIso8601String(),
        'issuing_authority': issuingAuthority,
        'monthly_fee': monthlyFee,
      }),
    );

    if (response.statusCode == 201) {
      return ExciseLicense.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to create license: ${response.body}');
    }
  }

  /// Update license
  Future<ExciseLicense> updateLicense({
    required String id,
    String? licenseNumber,
    DateTime? expiryDate,
    String? issuingAuthority,
    double? monthlyFee,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/excise/licenses/$id'),
      headers: await _headers,
      body: json.encode({
        if (licenseNumber != null) 'license_number': licenseNumber,
        if (expiryDate != null) 'expiry_date': expiryDate.toIso8601String(),
        if (issuingAuthority != null) 'issuing_authority': issuingAuthority,
        if (monthlyFee != null) 'monthly_fee': monthlyFee,
      }),
    );

    if (response.statusCode == 200) {
      return ExciseLicense.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to update license: ${response.body}');
    }
  }

  /// Renew license
  Future<ExciseLicense> renewLicense({
    required String id,
    required DateTime newExpiryDate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/excise/licenses/$id/renew'),
      headers: await _headers,
      body: json.encode({
        'new_expiry_date': newExpiryDate.toIso8601String(),
      }),
    );

    if (response.statusCode == 200) {
      return ExciseLicense.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to renew license: ${response.body}');
    }
  }

  /// Pay license fee
  Future<void> payLicenseFee({
    required String licenseId,
    required double amount,
    required String paymentMethod,
    required String transactionRef,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/excise/licenses/pay-fee'),
      headers: await _headers,
      body: json.encode({
        'license_id': licenseId,
        'amount': amount,
        'payment_method': paymentMethod,
        'transaction_ref': transactionRef,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to pay license fee: ${response.body}');
    }
  }

  /// Get license fee payments
  Future<List<Map<String, dynamic>>> getLicenseFeePayments(String licenseId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/excise/licenses/$licenseId/fee-payments'),
      headers: await _headers,
    );

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    } else {
      throw Exception('Failed to load fee payments: ${response.body}');
    }
  }

  /// Get license compliance status
  Future<Map<String, dynamic>> getLicenseComplianceStatus(String licenseId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/excise/licenses/$licenseId/compliance-status'),
      headers: await _headers,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load compliance status: ${response.body}');
    }
  }

  // ==================== DAILY REPORTS ====================

  /// Get all daily reports
  Future<List<ExciseDailyReport>> getDailyReports({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (shopId != null) queryParams['shop_id'] = shopId;
    if (startDate != null) queryParams['start_date'] = startDate.toIso8601String();
    if (endDate != null) queryParams['end_date'] = endDate.toIso8601String();

    final uri = Uri.parse('$baseUrl/api/excise/daily-reports')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: await _headers);

    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((json) => ExciseDailyReport.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load daily reports: ${response.body}');
    }
  }

  /// Auto-generate daily report (ZERO manual entry!)
  Future<ExciseDailyReport> autoGenerateDailyReport({
    required String shopId,
    required DateTime reportDate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/excise/daily-reports/auto-generate'),
      headers: await _headers,
      body: json.encode({
        'shop_id': shopId,
        'report_date': reportDate.toIso8601String(),
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return ExciseDailyReport.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to auto-generate report: ${response.body}');
    }
  }

  /// Get daily report by date
  Future<ExciseDailyReport> getDailyReportByDate({
    required String shopId,
    required DateTime date,
  }) async {
    final dateStr = date.toIso8601String().split('T')[0]; // YYYY-MM-DD
    final response = await http.get(
      Uri.parse('$baseUrl/api/excise/daily-reports/date/$dateStr?shop_id=$shopId'),
      headers: await _headers,
    );

    if (response.statusCode == 200) {
      return ExciseDailyReport.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load daily report: ${response.body}');
    }
  }

  /// Get daily report by ID
  Future<ExciseDailyReport> getDailyReportById(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/excise/daily-reports/$id'),
      headers: await _headers,
    );

    if (response.statusCode == 200) {
      return ExciseDailyReport.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load daily report: ${response.body}');
    }
  }

  /// Upload report to UP Excise portal
  Future<ExciseDailyReport> uploadReportToPortal(String reportId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/excise/daily-reports/$reportId/upload-to-portal'),
      headers: await _headers,
    );

    if (response.statusCode == 200) {
      return ExciseDailyReport.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to upload report: ${response.body}');
    }
  }

  /// Retry report upload
  Future<ExciseDailyReport> retryReportUpload(String reportId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/excise/daily-reports/$reportId/retry-upload'),
      headers: await _headers,
    );

    if (response.statusCode == 200) {
      return ExciseDailyReport.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to retry upload: ${response.body}');
    }
  }

  // ==================== SECURITY CODES ====================

  /// Validate security code
  Future<SecurityCode> validateSecurityCode(String code) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/excise/security-codes/validate'),
      headers: await _headers,
      body: json.encode({'code': code}),
    );

    if (response.statusCode == 200) {
      return SecurityCode.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to validate security code: ${response.body}');
    }
  }

  /// Bulk add security codes
  Future<Map<String, dynamic>> bulkAddSecurityCodes({
    required String shopId,
    required String productId,
    required List<String> codes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/excise/security-codes/bulk-add'),
      headers: await _headers,
      body: json.encode({
        'shop_id': shopId,
        'product_id': productId,
        'codes': codes,
      }),
    );

    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to bulk add security codes: ${response.body}');
    }
  }

  /// Get security code details
  Future<SecurityCode> getSecurityCode(String code) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/excise/security-codes/$code'),
      headers: await _headers,
    );

    if (response.statusCode == 200) {
      return SecurityCode.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load security code: ${response.body}');
    }
  }

  /// Search security codes
  Future<List<SecurityCode>> searchSecurityCodes({
    String? shopId,
    String? productId,
    SecurityCodeStatus? status,
  }) async {
    final queryParams = <String, String>{};
    if (shopId != null) queryParams['shop_id'] = shopId;
    if (productId != null) queryParams['product_id'] = productId;
    if (status != null) queryParams['status'] = status.value;

    final uri = Uri.parse('$baseUrl/api/excise/security-codes/search')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: await _headers);

    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((json) => SecurityCode.fromJson(json)).toList();
    } else {
      throw Exception('Failed to search security codes: ${response.body}');
    }
  }

  /// Mark security codes as sold
  Future<void> markSecurityCodesAsSold({
    required List<String> codes,
    required String saleId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/excise/security-codes/mark-sold'),
      headers: await _headers,
      body: json.encode({
        'codes': codes,
        'sale_id': saleId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark codes as sold: ${response.body}');
    }
  }

  /// Mark security codes as damaged
  Future<void> markSecurityCodesAsDamaged({
    required List<String> codes,
    required String reason,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/excise/security-codes/mark-damaged'),
      headers: await _headers,
      body: json.encode({
        'codes': codes,
        'reason': reason,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark codes as damaged: ${response.body}');
    }
  }

  /// Get security code statistics
  Future<SecurityCodeStats> getSecurityCodeStats({String? shopId}) async {
    final uri = Uri.parse('$baseUrl/api/excise/security-codes/stats')
        .replace(queryParameters: shopId != null ? {'shop_id': shopId} : null);

    final response = await http.get(uri, headers: await _headers);

    if (response.statusCode == 200) {
      return SecurityCodeStats.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load security code stats: ${response.body}');
    }
  }

  // ==================== COMPLIANCE MONITORING ====================

  /// Get compliance dashboard
  Future<ComplianceDashboard> getComplianceDashboard({String? shopId}) async {
    final uri = Uri.parse('$baseUrl/api/excise/compliance/dashboard')
        .replace(queryParameters: shopId != null ? {'shop_id': shopId} : null);

    final response = await http.get(uri, headers: await _headers);

    if (response.statusCode == 200) {
      return ComplianceDashboard.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load compliance dashboard: ${response.body}');
    }
  }

  /// Get compliance logs
  Future<List<ComplianceLog>> getComplianceLogs({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (shopId != null) queryParams['shop_id'] = shopId;
    if (startDate != null) queryParams['start_date'] = startDate.toIso8601String();
    if (endDate != null) queryParams['end_date'] = endDate.toIso8601String();

    final uri = Uri.parse('$baseUrl/api/excise/compliance/logs')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: await _headers);

    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((json) => ComplianceLog.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load compliance logs: ${response.body}');
    }
  }

  /// Get expiring licenses (30-day warning)
  Future<List<ExciseLicense>> getExpiringLicenses({int? days}) async {
    final uri = Uri.parse('$baseUrl/api/excise/compliance/expiring-licenses')
        .replace(queryParameters: days != null ? {'days': days.toString()} : null);

    final response = await http.get(uri, headers: await _headers);

    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((json) => ExciseLicense.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load expiring licenses: ${response.body}');
    }
  }

  /// Get pending license fees
  Future<List<Map<String, dynamic>>> getPendingLicenseFees() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/excise/compliance/pending-fees'),
      headers: await _headers,
    );

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    } else {
      throw Exception('Failed to load pending fees: ${response.body}');
    }
  }

  /// Get consideration fee summary (₹50/bottle)
  Future<Map<String, dynamic>> getConsiderationFeeSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['start_date'] = startDate.toIso8601String();
    if (endDate != null) queryParams['end_date'] = endDate.toIso8601String();

    final uri = Uri.parse('$baseUrl/api/excise/compliance/consideration-fees')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: await _headers);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load consideration fee summary: ${response.body}');
    }
  }

  /// Get complete compliance report
  Future<Map<String, dynamic>> getComplianceReport({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (shopId != null) queryParams['shop_id'] = shopId;
    if (startDate != null) queryParams['start_date'] = startDate.toIso8601String();
    if (endDate != null) queryParams['end_date'] = endDate.toIso8601String();

    final uri = Uri.parse('$baseUrl/api/excise/compliance/report')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: await _headers);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load compliance report: ${response.body}');
    }
  }

  // ==================== HEALTH CHECK ====================

  /// Health check (public endpoint)
  Future<Map<String, dynamic>> healthCheck() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/excise/health'),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Health check failed: ${response.body}');
    }
  }
}

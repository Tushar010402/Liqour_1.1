# Flutter Integration Guide - UP Excise Compliance Module

**Date:** October 3, 2025
**Backend Service:** Inventory Service (Port 8093)
**API Prefix:** `/api/excise`
**Version:** 1.0.0

---

## 📱 Overview

This guide helps Flutter developers integrate the UP Excise Compliance backend into the LiquorPro mobile application.

---

## 🔑 Authentication

All excise endpoints require JWT authentication. Use the existing auth flow:

### Login Flow
```dart
// 1. Login via Auth Service
final response = await http.post(
  Uri.parse('$AUTH_BASE_URL/api/auth/login'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'email': 'shop.owner@upexcise.test',
    'password': 'test123',
  }),
);

final data = jsonDecode(response.body);
final token = data['token'];
final tenantId = data['user']['tenant_id'];

// 2. Store token for subsequent requests
await secureStorage.write(key: 'jwt_token', value: token);
await secureStorage.write(key: 'tenant_id', value: tenantId);
```

### Authenticated Requests
```dart
final token = await secureStorage.read(key: 'jwt_token');

final response = await http.get(
  Uri.parse('$EXCISE_BASE_URL/api/excise/licenses'),
  headers: {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  },
);
```

---

## 📊 Data Models

### 1. Excise License Model
```dart
class ExciseLicense {
  final String id;
  final String tenantId;
  final String shopId;
  final String licenseNumber;
  final String licenseType; // FL-2A, FL-17, CL-2, COMPOSITE
  final DateTime issuedDate;
  final DateTime expiryDate;
  final bool isActive;
  final double monthlyFee;
  final String? bankAccountId;
  final Map<String, dynamic>? restrictions;
  final String? licenseConditions;
  final String? issuingAuthority;
  final String? licenseCategory;
  final DateTime createdAt;
  final DateTime updatedAt;

  ExciseLicense({
    required this.id,
    required this.tenantId,
    required this.shopId,
    required this.licenseNumber,
    required this.licenseType,
    required this.issuedDate,
    required this.expiryDate,
    required this.isActive,
    required this.monthlyFee,
    this.bankAccountId,
    this.restrictions,
    this.licenseConditions,
    this.issuingAuthority,
    this.licenseCategory,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExciseLicense.fromJson(Map<String, dynamic> json) {
    return ExciseLicense(
      id: json['id'],
      tenantId: json['tenant_id'],
      shopId: json['shop_id'],
      licenseNumber: json['license_number'],
      licenseType: json['license_type'],
      issuedDate: DateTime.parse(json['issued_date']),
      expiryDate: DateTime.parse(json['expiry_date']),
      isActive: json['is_active'] ?? true,
      monthlyFee: (json['monthly_fee'] as num).toDouble(),
      bankAccountId: json['bank_account_id'],
      restrictions: json['restrictions'],
      licenseConditions: json['license_conditions'],
      issuingAuthority: json['issuing_authority'],
      licenseCategory: json['license_category'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'shop_id': shopId,
      'license_number': licenseNumber,
      'license_type': licenseType,
      'issued_date': issuedDate.toIso8601String(),
      'expiry_date': expiryDate.toIso8601String(),
      'is_active': isActive,
      'monthly_fee': monthlyFee,
      'bank_account_id': bankAccountId,
      'restrictions': restrictions,
      'license_conditions': licenseConditions,
      'issuing_authority': issuingAuthority,
      'license_category': licenseCategory,
    };
  }

  // Helper methods
  bool get isExpiringSoon {
    final daysUntilExpiry = expiryDate.difference(DateTime.now()).inDays;
    return daysUntilExpiry <= 30 && daysUntilExpiry > 0;
  }

  bool get isExpired {
    return DateTime.now().isAfter(expiryDate);
  }

  int get daysUntilExpiry {
    return expiryDate.difference(DateTime.now()).inDays;
  }

  Color get statusColor {
    if (isExpired) return Colors.red;
    if (isExpiringSoon) return Colors.orange;
    return Colors.green;
  }

  String get statusText {
    if (isExpired) return 'Expired';
    if (isExpiringSoon) return 'Expiring Soon';
    return 'Active';
  }
}
```

### 2. Daily Report Model
```dart
class StockEntry {
  final String productId;
  final String productName;
  final int quantity;
  final double value;

  StockEntry({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.value,
  });

  factory StockEntry.fromJson(Map<String, dynamic> json) {
    return StockEntry(
      productId: json['product_id'],
      productName: json['product_name'],
      quantity: json['quantity'],
      value: (json['value'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'value': value,
    };
  }
}

class StockBreakdown {
  final List<StockEntry> countryLiquor;
  final List<StockEntry> imfl;
  final List<StockEntry> beer;
  final List<StockEntry> wine;
  final List<StockEntry> lowAlcohol;

  StockBreakdown({
    required this.countryLiquor,
    required this.imfl,
    required this.beer,
    required this.wine,
    required this.lowAlcohol,
  });

  factory StockBreakdown.fromJson(Map<String, dynamic> json) {
    return StockBreakdown(
      countryLiquor: (json['country_liquor'] as List? ?? [])
          .map((e) => StockEntry.fromJson(e))
          .toList(),
      imfl: (json['imfl'] as List? ?? [])
          .map((e) => StockEntry.fromJson(e))
          .toList(),
      beer: (json['beer'] as List? ?? [])
          .map((e) => StockEntry.fromJson(e))
          .toList(),
      wine: (json['wine'] as List? ?? [])
          .map((e) => StockEntry.fromJson(e))
          .toList(),
      lowAlcohol: (json['low_alcohol'] as List? ?? [])
          .map((e) => StockEntry.fromJson(e))
          .toList(),
    );
  }
}

class ExciseDailyReport {
  final String id;
  final String shopId;
  final String licenseId;
  final DateTime reportDate;
  final StockBreakdown openingStock;
  final StockBreakdown stockLifted;
  final StockBreakdown sales;
  final StockBreakdown returns;
  final StockBreakdown closingStock;
  final double considerationFeePaid;
  final bool uploadedToPortal;
  final int uploadAttempts;
  final DateTime? uploadTimestamp;
  final String? smsConfirmation;
  final String? portalResponse;

  ExciseDailyReport({
    required this.id,
    required this.shopId,
    required this.licenseId,
    required this.reportDate,
    required this.openingStock,
    required this.stockLifted,
    required this.sales,
    required this.returns,
    required this.closingStock,
    required this.considerationFeePaid,
    required this.uploadedToPortal,
    required this.uploadAttempts,
    this.uploadTimestamp,
    this.smsConfirmation,
    this.portalResponse,
  });

  factory ExciseDailyReport.fromJson(Map<String, dynamic> json) {
    return ExciseDailyReport(
      id: json['id'],
      shopId: json['shop_id'],
      licenseId: json['license_id'],
      reportDate: DateTime.parse(json['report_date']),
      openingStock: StockBreakdown.fromJson(json['opening_stock']),
      stockLifted: StockBreakdown.fromJson(json['stock_lifted']),
      sales: StockBreakdown.fromJson(json['sales']),
      returns: StockBreakdown.fromJson(json['returns']),
      closingStock: StockBreakdown.fromJson(json['closing_stock']),
      considerationFeePaid: (json['consideration_fee_paid'] as num).toDouble(),
      uploadedToPortal: json['uploaded_to_portal'] ?? false,
      uploadAttempts: json['upload_attempts'] ?? 0,
      uploadTimestamp: json['upload_timestamp'] != null
          ? DateTime.parse(json['upload_timestamp'])
          : null,
      smsConfirmation: json['sms_confirmation'],
      portalResponse: json['portal_response'],
    );
  }
}
```

### 3. Compliance Dashboard Model
```dart
class ComplianceDashboard {
  final String tenantId;
  final int totalShops;
  final int activeShops;
  final int activeLicenses;
  final int expiringLicenses;
  final int pendingReports;
  final int pendingLicenseFees;
  final double overdueFeesAmount;
  final double complianceScore;
  final String complianceStatus; // excellent, good, needs_attention, critical
  final DateTime? lastReportDate;

  ComplianceDashboard({
    required this.tenantId,
    required this.totalShops,
    required this.activeShops,
    required this.activeLicenses,
    required this.expiringLicenses,
    required this.pendingReports,
    required this.pendingLicenseFees,
    required this.overdueFeesAmount,
    required this.complianceScore,
    required this.complianceStatus,
    this.lastReportDate,
  });

  factory ComplianceDashboard.fromJson(Map<String, dynamic> json) {
    return ComplianceDashboard(
      tenantId: json['tenant_id'],
      totalShops: json['total_shops'],
      activeShops: json['active_shops'],
      activeLicenses: json['active_licenses'],
      expiringLicenses: json['expiring_licenses'],
      pendingReports: json['pending_reports'],
      pendingLicenseFees: json['pending_license_fees'],
      overdueFeesAmount: (json['overdue_fees_amount'] as num).toDouble(),
      complianceScore: (json['compliance_score'] as num).toDouble(),
      complianceStatus: json['compliance_status'],
      lastReportDate: json['last_report_date'] != null
          ? DateTime.parse(json['last_report_date'])
          : null,
    );
  }

  Color get scoreColor {
    if (complianceScore >= 90) return Colors.green;
    if (complianceScore >= 70) return Colors.orange;
    return Colors.red;
  }

  IconData get scoreIcon {
    if (complianceScore >= 90) return Icons.check_circle;
    if (complianceScore >= 70) return Icons.warning;
    return Icons.error;
  }
}
```

### 4. Security Code Model
```dart
class SecurityCode {
  final String id;
  final String securityCode;
  final String productId;
  final String status; // in_stock, sold, damaged, missing, returned
  final DateTime? receivedDate;
  final String? warehouseSource;
  final String? batchNumber;
  final bool verified;
  final DateTime? soldDate;
  final String? saleId;

  SecurityCode({
    required this.id,
    required this.securityCode,
    required this.productId,
    required this.status,
    this.receivedDate,
    this.warehouseSource,
    this.batchNumber,
    required this.verified,
    this.soldDate,
    this.saleId,
  });

  factory SecurityCode.fromJson(Map<String, dynamic> json) {
    return SecurityCode(
      id: json['id'],
      securityCode: json['security_code'],
      productId: json['product_id'],
      status: json['status'],
      receivedDate: json['received_date'] != null
          ? DateTime.parse(json['received_date'])
          : null,
      warehouseSource: json['warehouse_source'],
      batchNumber: json['batch_number'],
      verified: json['verified'] ?? false,
      soldDate: json['sold_date'] != null
          ? DateTime.parse(json['sold_date'])
          : null,
      saleId: json['sale_id'],
    );
  }

  Color get statusColor {
    switch (status) {
      case 'in_stock':
        return Colors.green;
      case 'sold':
        return Colors.blue;
      case 'damaged':
        return Colors.red;
      case 'missing':
        return Colors.orange;
      case 'returned':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case 'in_stock':
        return Icons.inventory;
      case 'sold':
        return Icons.shopping_cart;
      case 'damaged':
        return Icons.broken_image;
      case 'missing':
        return Icons.search_off;
      case 'returned':
        return Icons.keyboard_return;
      default:
        return Icons.help_outline;
    }
  }
}
```

---

## 🔌 API Service Class

```dart
class ExciseApiService {
  static const String baseUrl = 'http://localhost:8093/api/excise';
  final SecureStorage _storage;

  ExciseApiService(this._storage);

  Future<Map<String, String>> _getHeaders() async {
    final token = await _storage.read(key: 'jwt_token');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // ==================== LICENSE MANAGEMENT ====================

  Future<List<ExciseLicense>> getLicenses() async {
    final response = await http.get(
      Uri.parse('$baseUrl/licenses'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((json) => ExciseLicense.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load licenses: ${response.body}');
    }
  }

  Future<ExciseLicense> getLicenseById(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/licenses/$id'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return ExciseLicense.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load license: ${response.body}');
    }
  }

  Future<ExciseLicense> createLicense({
    required String shopId,
    required String licenseNumber,
    required String licenseType,
    required DateTime issuedDate,
    required DateTime expiryDate,
    required double monthlyFee,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/licenses'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'shop_id': shopId,
        'license_number': licenseNumber,
        'license_type': licenseType,
        'issued_date': issuedDate.toIso8601String(),
        'expiry_date': expiryDate.toIso8601String(),
        'monthly_fee': monthlyFee,
      }),
    );

    if (response.statusCode == 201) {
      return ExciseLicense.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create license: ${response.body}');
    }
  }

  Future<void> payLicenseFee({
    required String licenseId,
    required double amount,
    required String paymentMethod,
    required DateTime paymentDate,
    required int month,
    required int year,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/licenses/pay-fee'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'license_id': licenseId,
        'amount': amount,
        'payment_method': paymentMethod,
        'payment_date': paymentDate.toIso8601String(),
        'month': month,
        'year': year,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to pay license fee: ${response.body}');
    }
  }

  // ==================== DAILY REPORTS ====================

  Future<List<ExciseDailyReport>> getDailyReports({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (shopId != null) queryParams['shop_id'] = shopId;
    if (startDate != null) {
      queryParams['start_date'] = startDate.toIso8601String();
    }
    if (endDate != null) {
      queryParams['end_date'] = endDate.toIso8601String();
    }

    final uri = Uri.parse('$baseUrl/daily-reports')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: await _getHeaders());

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((json) => ExciseDailyReport.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load reports: ${response.body}');
    }
  }

  Future<ExciseDailyReport> autoGenerateDailyReport({
    required String shopId,
    required DateTime reportDate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/daily-reports/auto-generate'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'shop_id': shopId,
        'report_date': reportDate.toIso8601String(),
      }),
    );

    if (response.statusCode == 201) {
      return ExciseDailyReport.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to generate report: ${response.body}');
    }
  }

  Future<void> uploadReportToPortal(String reportId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/daily-reports/$reportId/upload-to-portal'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to upload report: ${response.body}');
    }
  }

  // ==================== SECURITY CODES ====================

  Future<SecurityCode> validateSecurityCode(String code) async {
    final response = await http.post(
      Uri.parse('$baseUrl/security-codes/validate'),
      headers: await _getHeaders(),
      body: jsonEncode({'security_code': code}),
    );

    if (response.statusCode == 200) {
      return SecurityCode.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Invalid security code: ${response.body}');
    }
  }

  Future<void> bulkAddSecurityCodes({
    required String productId,
    required List<String> securityCodes,
    String? batchNumber,
    String? sourceWarehouse,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/security-codes/bulk-add'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'product_id': productId,
        'security_codes': securityCodes,
        'batch_number': batchNumber,
        'source_warehouse': sourceWarehouse,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to add security codes: ${response.body}');
    }
  }

  Future<Map<String, int>> getSecurityCodeStats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/security-codes/stats'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'total_codes': data['total_codes'] ?? 0,
        'in_stock': data['in_stock'] ?? 0,
        'sold': data['sold'] ?? 0,
        'damaged': data['damaged'] ?? 0,
        'missing': data['missing'] ?? 0,
        'returned': data['returned'] ?? 0,
      };
    } else {
      throw Exception('Failed to load stats: ${response.body}');
    }
  }

  // ==================== COMPLIANCE ====================

  Future<ComplianceDashboard> getComplianceDashboard() async {
    final response = await http.get(
      Uri.parse('$baseUrl/compliance/dashboard'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return ComplianceDashboard.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load dashboard: ${response.body}');
    }
  }

  Future<List<ExciseLicense>> getExpiringLicenses({int days = 30}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/compliance/expiring-licenses?days=$days'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((json) => ExciseLicense.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load expiring licenses: ${response.body}');
    }
  }
}
```

---

## 🎨 UI Screens (Examples)

### 1. Compliance Dashboard Screen
```dart
class ComplianceDashboardScreen extends StatefulWidget {
  @override
  _ComplianceDashboardScreenState createState() =>
      _ComplianceDashboardScreenState();
}

class _ComplianceDashboardScreenState extends State<ComplianceDashboardScreen> {
  final ExciseApiService _apiService = ExciseApiService(SecureStorage());
  ComplianceDashboard? _dashboard;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    try {
      final dashboard = await _apiService.getComplianceDashboard();
      setState(() {
        _dashboard = dashboard;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Compliance Dashboard')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_dashboard == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Compliance Dashboard')),
        body: Center(child: Text('Failed to load dashboard')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Compliance Dashboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadDashboard,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboard,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Compliance Score Card
              Card(
                elevation: 4,
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Compliance Score',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Icon(
                            _dashboard!.scoreIcon,
                            color: _dashboard!.scoreColor,
                            size: 32,
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: _dashboard!.complianceScore / 100,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _dashboard!.scoreColor,
                        ),
                        minHeight: 10,
                      ),
                      SizedBox(height: 8),
                      Text(
                        '${_dashboard!.complianceScore.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: _dashboard!.scoreColor,
                        ),
                      ),
                      Text(
                        _dashboard!.complianceStatus.toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),

              // Stats Grid
              GridView.count(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildStatCard(
                    'Active Licenses',
                    _dashboard!.activeLicenses.toString(),
                    Icons.verified,
                    Colors.green,
                  ),
                  _buildStatCard(
                    'Expiring Soon',
                    _dashboard!.expiringLicenses.toString(),
                    Icons.warning,
                    Colors.orange,
                  ),
                  _buildStatCard(
                    'Pending Reports',
                    _dashboard!.pendingReports.toString(),
                    Icons.description,
                    _dashboard!.pendingReports > 0 ? Colors.red : Colors.green,
                  ),
                  _buildStatCard(
                    'Pending Fees',
                    _dashboard!.pendingLicenseFees.toString(),
                    Icons.payment,
                    _dashboard!.pendingLicenseFees > 0 ? Colors.red : Colors.green,
                  ),
                ],
              ),

              SizedBox(height: 16),

              // Quick Actions
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.description, color: Colors.blue),
                      title: Text('Generate Daily Report'),
                      trailing: Icon(Icons.chevron_right),
                      onTap: () {
                        // Navigate to daily report generation
                      },
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.payment, color: Colors.green),
                      title: Text('Pay License Fee'),
                      trailing: Icon(Icons.chevron_right),
                      onTap: () {
                        // Navigate to payment screen
                      },
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.qr_code_scanner, color: Colors.purple),
                      title: Text('Scan Security Code'),
                      trailing: Icon(Icons.chevron_right),
                      onTap: () {
                        // Open barcode scanner
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 2. Auto-Generate Daily Report Screen
```dart
class GenerateDailyReportScreen extends StatefulWidget {
  final String shopId;

  GenerateDailyReportScreen({required this.shopId});

  @override
  _GenerateDailyReportScreenState createState() =>
      _GenerateDailyReportScreenState();
}

class _GenerateDailyReportScreenState extends State<GenerateDailyReportScreen> {
  final ExciseApiService _apiService = ExciseApiService(SecureStorage());
  DateTime _selectedDate = DateTime.now().subtract(Duration(days: 1));
  bool _generating = false;
  ExciseDailyReport? _generatedReport;

  Future<void> _generateReport() async {
    setState(() => _generating = true);

    try {
      final report = await _apiService.autoGenerateDailyReport(
        shopId: widget.shopId,
        reportDate: _selectedDate,
      );

      setState(() {
        _generatedReport = report;
        _generating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report generated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _uploadToPortal() async {
    if (_generatedReport == null) return;

    try {
      await _apiService.uploadReportToPortal(_generatedReport!.id);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uploaded to UP Excise Portal successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh report to get SMS confirmation
      setState(() => _generatedReport = null);
      await _generateReport();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Generate Daily Report')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Report Date',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            ListTile(
              tileColor: Colors.grey[100],
              leading: Icon(Icons.calendar_today),
              title: Text(
                DateFormat('EEEE, MMMM dd, yyyy').format(_selectedDate),
              ),
              trailing: Icon(Icons.edit),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now().subtract(Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _selectedDate = date);
                }
              },
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generating ? null : _generateReport,
                icon: _generating
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Icon(Icons.auto_awesome),
                label: Text(_generating ? 'Generating...' : 'Auto-Generate Report'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.all(16),
                ),
              ),
            ),
            SizedBox(height: 16),
            if (_generatedReport != null) ...[
              Divider(),
              Text(
                'Generated Report Summary',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              _buildReportSummary(_generatedReport!),
              SizedBox(height: 16),
              if (!_generatedReport!.uploadedToPortal)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _uploadToPortal,
                    icon: Icon(Icons.cloud_upload),
                    label: Text('Upload to UP Excise Portal'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.all(16),
                    ),
                  ),
                ),
              if (_generatedReport!.uploadedToPortal)
                Card(
                  color: Colors.green[50],
                  child: ListTile(
                    leading: Icon(Icons.check_circle, color: Colors.green),
                    title: Text('Uploaded to Portal'),
                    subtitle: Text(
                      'SMS: ${_generatedReport!.smsConfirmation ?? 'N/A'}',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReportSummary(ExciseDailyReport report) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSummaryRow(
              'Opening Stock',
              _getTotalQuantity(report.openingStock),
            ),
            _buildSummaryRow(
              'Stock Lifted',
              _getTotalQuantity(report.stockLifted),
            ),
            _buildSummaryRow('Sales', _getTotalQuantity(report.sales)),
            _buildSummaryRow('Returns', _getTotalQuantity(report.returns)),
            Divider(),
            _buildSummaryRow(
              'Closing Stock',
              _getTotalQuantity(report.closingStock),
              bold: true,
            ),
            Divider(),
            _buildSummaryRow(
              'Consideration Fee',
              '₹${report.considerationFeePaid.toStringAsFixed(2)}',
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  String _getTotalQuantity(StockBreakdown breakdown) {
    int total = 0;
    total += breakdown.countryLiquor.fold(0, (sum, e) => sum + e.quantity);
    total += breakdown.imfl.fold(0, (sum, e) => sum + e.quantity);
    total += breakdown.beer.fold(0, (sum, e) => sum + e.quantity);
    total += breakdown.wine.fold(0, (sum, e) => sum + e.quantity);
    total += breakdown.lowAlcohol.fold(0, (sum, e) => sum + e.quantity);
    return '$total bottles';
  }
}
```

---

## 📝 Testing Guide

### 1. Test with Mock Data
```dart
// Use test credentials
final testEmail = 'shop.owner@upexcise.test';
final testPassword = 'test123';
final testTenantId = '11111111-1111-1111-1111-111111111111';
```

### 2. Test Scenarios
1. Login → View Compliance Dashboard
2. Generate Daily Report for yesterday
3. View license expiry alerts
4. Scan security code (use: UP2025ABC001234)
5. Upload report to portal
6. Pay license fee

### 3. Error Handling
Always wrap API calls in try-catch:
```dart
try {
  final result = await _apiService.someMethod();
  // Handle success
} on SocketException {
  // Handle network error
} on HttpException {
  // Handle HTTP error
} catch (e) {
  // Handle general error
}
```

---

## 🎯 Next Steps

1. ✅ Implement authentication flow
2. ✅ Build compliance dashboard UI
3. ✅ Add daily report generation screen
4. ⏳ Implement barcode scanner for security codes
5. ⏳ Add license management screens
6. ⏳ Build payment integration
7. ⏳ Add push notifications for alerts

---

*Last Updated: October 3, 2025*
*Backend Version: 1.0.0*
*Service: Running on port 8093*

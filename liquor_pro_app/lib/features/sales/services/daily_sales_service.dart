import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../core/config/api_config.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/app_logger.dart';
import '../models/daily_sales_models.dart';

/// Daily Sales Service - Handles API calls for bulk daily sales entry
class DailySalesService {
  final AuthService _authService;

  DailySalesService(this._authService);

  /// Create new daily sales record
  Future<ApiResponse<DailySalesRecord>> createDailySalesRecord(
    DailySalesRecordRequest request,
  ) async {
    try {
      print('🌐 [DailySalesService] ========== API CALL START ==========');
      AppLogger.info('Creating daily sales record for ${request.recordDate}');
      print('🌐 [DailySalesService] Record Date: ${request.recordDate}');
      print('🌐 [DailySalesService] Shop ID: ${request.shopId}');
      print('🌐 [DailySalesService] Total Amount: ${request.totalSalesAmount}');

      final requestJson = request.toJson();
      final jsonString = json.encode(requestJson);
      print('🌐 [DailySalesService] Request JSON length: ${jsonString.length} characters');
      AppLogger.info('Request JSON: $jsonString');

      print('🌐 [DailySalesService] Getting authentication token...');
      final token = await _authService.getToken();
      if (token == null) {
        print('❌ [DailySalesService] Authentication failed - no token');
        return ApiResponse.error(error: 'Not authenticated');
      }
      print('✅ [DailySalesService] Token obtained: ${token.substring(0, 20)}...');

      print('🌐 [DailySalesService] Getting tenant ID...');
      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        print('❌ [DailySalesService] Tenant ID not found');
        return ApiResponse.error(error: 'Tenant ID not found');
      }
      print('✅ [DailySalesService] Tenant ID: $tenantId');

      final url = '${ApiConfig.baseUrl}/api/sales/daily-records';
      print('🌐 [DailySalesService] API URL: $url');
      print('🌐 [DailySalesService] Headers:');
      print('   Content-Type: application/json');
      print('   Authorization: Bearer ${token.substring(0, 20)}...');
      print('   X-Tenant-ID: $tenantId');

      print('🌐 [DailySalesService] Sending POST request...');
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
        body: jsonString,
      );

      print('🌐 [DailySalesService] Response received');
      print('   📊 Status Code: ${response.statusCode}');
      print('   📄 Body length: ${response.body.length} characters');
      AppLogger.info('Create daily sales response: ${response.statusCode}');
      AppLogger.info('Response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('✅ [DailySalesService] Success response - parsing data...');
        final data = json.decode(response.body);
        print('   🔍 Response structure: ${data.keys.toList()}');
        final record = DailySalesRecord.fromJson(data['data'] ?? data);
        print('✅ [DailySalesService] Record parsed successfully - ID: ${record.id}');
        print('🌐 [DailySalesService] ========== API CALL SUCCESS ==========\n');
        return ApiResponse.success(record);
      } else {
        print('❌ [DailySalesService] Error response (${response.statusCode})');
        final error = json.decode(response.body);
        print('   ❌ Error details: $error');
        AppLogger.error('API Error: ${error}');
        print('🌐 [DailySalesService] ========== API CALL FAILED ==========\n');
        return ApiResponse.error(error: error['error'] ?? error['errors']?.toString() ?? 'Failed to create daily sales record');
      }
    } catch (e, stackTrace) {
      print('❌ [DailySalesService] Exception during API call: $e');
      print('   Stack trace: $stackTrace');
      AppLogger.error('Error creating daily sales record: $e');
      print('🌐 [DailySalesService] ========== API CALL EXCEPTION ==========\n');
      return ApiResponse.error(error: 'Error creating daily sales record: $e');
    }
  }

  /// Get daily sales records with filters
  Future<ApiResponse<List<DailySalesRecord>>> getDailySalesRecords({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      AppLogger.info('Fetching daily sales records');

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final queryParams = <String, String>{
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };

      if (shopId != null) queryParams['shop_id'] = shopId;
      if (startDate != null) queryParams['start_date'] = startDate.toIso8601String();
      if (endDate != null) queryParams['end_date'] = endDate.toIso8601String();
      if (status != null) queryParams['status'] = status;

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/sales/daily-records')
          .replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      AppLogger.info('Get daily sales response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final recordsData = data['data']['records'] as List;
        final records = recordsData
            .map((record) => DailySalesRecord.fromJson(record))
            .toList();
        return ApiResponse.success(records);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? 'Failed to fetch daily sales records');
      }
    } catch (e) {
      AppLogger.error('Error fetching daily sales records: $e');
      return ApiResponse.error(error: 'Error fetching daily sales records: $e');
    }
  }

  /// Get daily sales record by ID
  Future<ApiResponse<DailySalesRecord>> getDailySalesRecordById(String id) async {
    try {
      AppLogger.info('Fetching daily sales record: $id');

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/sales/daily-records/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      AppLogger.info('Get daily sales record response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final record = DailySalesRecord.fromJson(data['data']);
        return ApiResponse.success(record);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? 'Failed to fetch daily sales record');
      }
    } catch (e) {
      AppLogger.error('Error fetching daily sales record: $e');
      return ApiResponse.error(error: 'Error fetching daily sales record: $e');
    }
  }

  /// Update daily sales record
  Future<ApiResponse<DailySalesRecord>> updateDailySalesRecord(
    String id,
    DailySalesRecordRequest request,
  ) async {
    try {
      AppLogger.info('Updating daily sales record: $id');

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/sales/daily-records/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
        body: json.encode(request.toJson()),
      );

      AppLogger.info('Update daily sales response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final record = DailySalesRecord.fromJson(data['data']);
        return ApiResponse.success(record);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? 'Failed to update daily sales record');
      }
    } catch (e) {
      AppLogger.error('Error updating daily sales record: $e');
      return ApiResponse.error(error: 'Error updating daily sales record: $e');
    }
  }

  /// Approve daily sales record (Manager only)
  Future<ApiResponse<DailySalesRecord>> approveDailySalesRecord(String id) async {
    try {
      AppLogger.info('Approving daily sales record: $id');

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/sales/daily-records/$id/approve'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      AppLogger.info('Approve daily sales response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final record = DailySalesRecord.fromJson(data['data']);
        return ApiResponse.success(record);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? 'Failed to approve daily sales record');
      }
    } catch (e) {
      AppLogger.error('Error approving daily sales record: $e');
      return ApiResponse.error(error: 'Error approving daily sales record: $e');
    }
  }

  /// Reject daily sales record (Manager only)
  Future<ApiResponse<void>> rejectDailySalesRecord(String id, String reason) async {
    try {
      AppLogger.info('Rejecting daily sales record: $id');

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/sales/daily-records/$id/reject'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
        body: json.encode({'reason': reason}),
      );

      AppLogger.info('Reject daily sales response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return ApiResponse.success(null);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? 'Failed to reject daily sales record');
      }
    } catch (e) {
      AppLogger.error('Error rejecting daily sales record: $e');
      return ApiResponse.error(error: 'Error rejecting daily sales record: $e');
    }
  }
}

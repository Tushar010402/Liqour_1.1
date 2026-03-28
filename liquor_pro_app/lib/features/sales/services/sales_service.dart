import 'dart:convert';
import '../../../core/models/api_response.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/app_logger.dart';
import '../models/sale.dart';

/// Sales service properly aligned with backend API
class SalesService {
  final DioApiService _apiService;

  SalesService(this._apiService);

  // Base URL for sales service (via gateway)
  static const String _baseUrl = '/api/sales';

  // ===== Individual Sales Operations =====

  /// Get all sales with optional filters - matches backend SalesFilters
  Future<ApiResponse<List<Sale>>> getSales({
    String? shopId,
    String? salesmanId,
    String? status,
    String? paymentStatus,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final params = <String, dynamic>{
        'page': page.toString(),
        'page_size': limit.toString(),
      };

      if (shopId != null && shopId.isNotEmpty) params['shop_id'] = shopId;
      if (salesmanId != null && salesmanId.isNotEmpty) params['salesman_id'] = salesmanId;
      if (status != null && status.isNotEmpty) params['status'] = status;
      if (paymentStatus != null && paymentStatus.isNotEmpty) params['payment_status'] = paymentStatus;
      if (startDate != null) params['start_date'] = startDate.toIso8601String();
      if (endDate != null) params['end_date'] = endDate.toIso8601String();

      AppLogger.info('Fetching sales with params: $params');

      final response = await _apiService.get<Map<String, dynamic>>(
        '$_baseUrl/sales',
        queryParams: params,
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        // Backend returns paginated response
        final salesData = response.data!['sales'] as List<dynamic>?;
        final sales = salesData?.map((item) =>
          Sale.fromJson(item as Map<String, dynamic>)
        ).toList() ?? [];

        return ApiResponse.success(
          sales,
          message: response.message,
        );
      }

      return ApiResponse.error(
        error: response.error ?? 'Failed to fetch sales',
      );
    } catch (e) {
      AppLogger.error('Error fetching sales', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Get sale by ID - matches backend GetSaleByID
  Future<ApiResponse<Sale>> getSaleById(String saleId) async {
    try {
      AppLogger.info('Fetching sale: $saleId');

      return await _apiService.get<Sale>(
        '$_baseUrl/sales/$saleId',
        fromJson: (data) => Sale.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      AppLogger.error('Error fetching sale by ID', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Create new sale - matches backend SaleRequest
  Future<ApiResponse<Sale>> createSale({
    required String shopId,
    String? salesmanId,
    required DateTime saleDate,
    String? customerName,
    String? customerPhone,
    required List<Map<String, dynamic>> items,
    required double subTotal,
    double discountAmount = 0,
    double taxAmount = 0,
    required double totalAmount,
    double paidAmount = 0,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    try {
      // Validate items structure matches backend SaleItemRequest
      final validatedItems = items.map((item) => {
        'product_id': item['product_id'],
        'quantity': item['quantity'],
        'unit_price': item['unit_price'],
        'discount_amount': item['discount_amount'] ?? 0,
        'discount_reason': item['discount_reason'] ?? '',
      }).toList();

      final data = {
        'sale_date': saleDate.toIso8601String(),
        'shop_id': shopId,
        if (salesmanId != null) 'salesman_id': salesmanId,
        if (customerName != null) 'customer_name': customerName,
        if (customerPhone != null) 'customer_phone': customerPhone,
        'payment_method': paymentMethod,
        'paid_amount': paidAmount,
        if (notes != null) 'notes': notes,
        'items': validatedItems,
      };

      AppLogger.info('Creating sale with data: ${jsonEncode(data)}');

      final response = await _apiService.post<Sale>(
        '$_baseUrl/sales',
        body: data,
        fromJson: (data) => Sale.fromJson(data as Map<String, dynamic>),
      );

      if (response.success) {
        AppLogger.info('Sale created successfully: ${response.data?.id}');
      } else {
        AppLogger.error('Failed to create sale: ${response.error}');
      }

      return response;
    } catch (e) {
      AppLogger.error('Error creating sale', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Update sale - matches backend UpdateSale (PUT /sales/:id)
  /// This is used for editing sales and resubmitting rejected sales
  Future<ApiResponse<Sale>> updateSale({
    required String saleId,
    String? customerName,
    String? customerPhone,
    String? notes,
    List<Map<String, dynamic>>? items,
    DateTime? recordDate,
  }) async {
    try {
      final data = <String, dynamic>{};

      // Add fields only if they are provided
      if (customerName != null) data['customer_name'] = customerName;
      if (customerPhone != null) data['customer_phone'] = customerPhone;
      if (notes != null) data['notes'] = notes;
      if (recordDate != null) data['record_date'] = recordDate.toIso8601String();

      // Format items array to match backend structure
      if (items != null) {
        data['items'] = items.map((item) => {
          'product_id': item['product_id'],
          'quantity': item['quantity'] ?? 1,
          'unit_price': item['unit_price'] ?? item['price'] ?? 0.0,
          'discount_amount': item['discount_amount'] ?? 0.0,
          'discount_reason': item['discount_reason'] ?? '',
        }).toList();
      }

      AppLogger.info('Updating sale: $saleId');

      return await _apiService.put<Sale>(
        '$_baseUrl/sales/$saleId',
        body: data,
        fromJson: (data) => Sale.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      AppLogger.error('Error updating sale', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Approve sale - matches backend ApproveSale
  Future<ApiResponse<Sale>> approveSale(String saleId) async {
    try {
      AppLogger.info('Approving sale: $saleId');

      return await _apiService.post<Sale>(
        '$_baseUrl/sales/$saleId/approve',
        fromJson: (data) => Sale.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      AppLogger.error('Error approving sale', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Reject sale - matches backend RejectSale
  Future<ApiResponse<void>> rejectSale(String saleId, String reason) async {
    try {
      AppLogger.info('Rejecting sale: $saleId, reason: $reason');

      return await _apiService.post<void>(
        '$_baseUrl/sales/$saleId/reject',
        body: {'reason': reason},
        fromJson: (_) {},
      );
    } catch (e) {
      AppLogger.error('Error rejecting sale', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Void sale (custom method)
  Future<ApiResponse<void>> voidSale(String saleId) async {
    return rejectSale(saleId, 'Sale voided');
  }

  /// Request OTP for sale revert - Admin only
  /// Sends different OTPs to both email and phone for security
  Future<ApiResponse<RevertOtpResponse>> requestRevertOtp(String saleId) async {
    try {
      AppLogger.info('Requesting revert OTP for sale: $saleId');

      return await _apiService.post<RevertOtpResponse>(
        '$_baseUrl/sales/$saleId/revert/request-otp',
        body: {},
        fromJson: (data) => RevertOtpResponse.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      AppLogger.error('Error requesting revert OTP', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Verify OTPs and revert sale - Admin only
  /// Requires both email and phone OTPs to be correct
  /// Max 3 attempts, OTPs expire after 10 minutes
  Future<ApiResponse<Map<String, dynamic>>> verifyAndRevertSale({
    required String saleId,
    required String emailOtp,
    required String phoneOtp,
    required String reason,
  }) async {
    try {
      AppLogger.info('Verifying OTPs and reverting sale: $saleId');

      return await _apiService.post<Map<String, dynamic>>(
        '$_baseUrl/sales/$saleId/revert',
        body: {
          'email_otp': emailOtp,
          'phone_otp': phoneOtp,
          'reason': reason,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );
    } catch (e) {
      AppLogger.error('Error verifying and reverting sale', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Resend OTP for sale revert - re-requests new OTPs
  Future<ApiResponse<RevertOtpResponse>> resendRevertOtp(String saleId) async {
    try {
      AppLogger.info('Resending revert OTP for sale: $saleId');

      // Just call request-otp again to get new OTPs
      return await _apiService.post<RevertOtpResponse>(
        '$_baseUrl/sales/$saleId/revert/request-otp',
        body: {},
        fromJson: (data) => RevertOtpResponse.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      AppLogger.error('Error resending revert OTP', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Get pending sales - matches backend GetPendingSales
  Future<ApiResponse<List<Sale>>> getPendingSales({String? shopId}) async {
    try {
      final params = <String, dynamic>{};
      if (shopId != null && shopId.isNotEmpty) params['shop_id'] = shopId;

      AppLogger.info('Fetching pending sales');

      return await _apiService.get<List<Sale>>(
        '$_baseUrl/pending/sales',
        queryParams: params,
        fromJson: (data) {
          if (data is List) {
            return data.map((item) => Sale.fromJson(item as Map<String, dynamic>)).toList();
          }
          return [];
        },
      );
    } catch (e) {
      AppLogger.error('Error fetching pending sales', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Get uncollected sales - matches backend GetUncollectedSales
  Future<ApiResponse<List<Sale>>> getUncollectedSales({String? shopId}) async {
    try {
      final params = <String, dynamic>{};
      if (shopId != null && shopId.isNotEmpty) params['shop_id'] = shopId;

      AppLogger.info('Fetching uncollected sales');

      return await _apiService.get<List<Sale>>(
        '$_baseUrl/uncollected',
        queryParams: params,
        fromJson: (data) {
          if (data is List) {
            return data.map((item) => Sale.fromJson(item as Map<String, dynamic>)).toList();
          }
          return [];
        },
      );
    } catch (e) {
      AppLogger.error('Error fetching uncollected sales', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  // ===== Daily Sales Records Operations =====

  /// Get daily sales records - matches backend GetDailySalesRecords
  Future<ApiResponse<List<DailySalesRecord>>> getDailySalesRecords({
    String? shopId,
    String? salesmanId,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final params = <String, dynamic>{
        'page': page.toString(),
        'page_size': limit.toString(),
      };

      if (shopId != null && shopId.isNotEmpty) params['shop_id'] = shopId;
      if (salesmanId != null && salesmanId.isNotEmpty) params['salesman_id'] = salesmanId;
      if (startDate != null) params['start_date'] = startDate.toIso8601String();
      if (endDate != null) params['end_date'] = endDate.toIso8601String();
      if (status != null && status.isNotEmpty) params['status'] = status;

      AppLogger.info('Fetching daily sales records');

      final response = await _apiService.get<Map<String, dynamic>>(
        '$_baseUrl/daily-sales',
        queryParams: params,
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        final recordsData = response.data!['records'] as List<dynamic>?;
        final records = recordsData?.map((item) =>
          DailySalesRecord.fromJson(item as Map<String, dynamic>)
        ).toList() ?? [];

        return ApiResponse.success(
          records,
          message: response.message,
        );
      }

      return ApiResponse.error(
        error: response.error ?? 'Failed to fetch daily records',
      );
    } catch (e) {
      AppLogger.error('Error fetching daily sales records', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Create daily sales record - matches backend CreateDailySalesRecord
  Future<ApiResponse<DailySalesRecord>> createDailySalesRecord({
    required String shopId,
    String? salesmanId,
    required DateTime recordDate,
    required double totalSalesAmount,
    double totalCashAmount = 0,
    double totalCardAmount = 0,
    double totalUpiAmount = 0,
    double totalCreditAmount = 0,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      // Validate items structure matches backend DailySalesItemRequest
      final validatedItems = items.map((item) => {
        'product_id': item['product_id'],
        'quantity': item['quantity'],
        'unit_price': item['unit_price'],
        'total_amount': item['total_amount'],
        'cash_amount': item['cash_amount'] ?? 0,
        'card_amount': item['card_amount'] ?? 0,
        'upi_amount': item['upi_amount'] ?? 0,
        'credit_amount': item['credit_amount'] ?? 0,
      }).toList();

      final data = {
        'record_date': recordDate.toIso8601String(),
        'shop_id': shopId,
        if (salesmanId != null) 'salesman_id': salesmanId,
        'total_sales_amount': totalSalesAmount,
        'total_cash_amount': totalCashAmount,
        'total_card_amount': totalCardAmount,
        'total_upi_amount': totalUpiAmount,
        'total_credit_amount': totalCreditAmount,
        if (notes != null) 'notes': notes,
        'items': validatedItems,
      };

      AppLogger.info('Creating daily sales record');

      return await _apiService.post<DailySalesRecord>(
        '$_baseUrl/daily-sales',
        body: data,
        fromJson: (data) => DailySalesRecord.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      AppLogger.error('Error creating daily sales record', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Approve daily sales record - matches backend ApproveDailySalesRecord
  Future<ApiResponse<DailySalesRecord>> approveDailySalesRecord(String recordId) async {
    try {
      AppLogger.info('Approving daily sales record: $recordId');

      return await _apiService.post<DailySalesRecord>(
        '$_baseUrl/daily-sales/$recordId/approve',
        fromJson: (data) => DailySalesRecord.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      AppLogger.error('Error approving daily sales record', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Reject daily sales record - matches backend RejectDailySalesRecord
  Future<ApiResponse<void>> rejectDailySalesRecord(String recordId, String reason) async {
    try {
      AppLogger.info('Rejecting daily sales record: $recordId');

      return await _apiService.post<void>(
        '$_baseUrl/daily-sales/$recordId/reject',
        body: {'reason': reason},
        fromJson: (_) {},
      );
    } catch (e) {
      AppLogger.error('Error rejecting daily sales record', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  // ===== Sale Returns Operations =====

  /// Get sale returns - matches backend GetSaleReturns
  Future<ApiResponse<List<SaleReturn>>> getSaleReturns({
    String? shopId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final params = <String, dynamic>{
        'page': page.toString(),
        'page_size': limit.toString(),
      };

      if (shopId != null && shopId.isNotEmpty) params['shop_id'] = shopId;
      if (status != null && status.isNotEmpty) params['status'] = status;
      if (startDate != null) params['start_date'] = startDate.toIso8601String();
      if (endDate != null) params['end_date'] = endDate.toIso8601String();

      AppLogger.info('Fetching sale returns');

      final response = await _apiService.get<Map<String, dynamic>>(
        '$_baseUrl/returns',
        queryParams: params,
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        final returnsData = response.data!['returns'] as List<dynamic>?;
        final returns = returnsData?.map((item) =>
          SaleReturn.fromJson(item as Map<String, dynamic>)
        ).toList() ?? [];

        return ApiResponse.success(
          returns,
          message: response.message,
        );
      }

      return ApiResponse.error(
        error: response.error ?? 'Failed to fetch returns',
      );
    } catch (e) {
      AppLogger.error('Error fetching sale returns', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Create sale return - matches backend CreateSaleReturn
  Future<ApiResponse<SaleReturn>> createSaleReturn({
    required String saleId,
    required String shopId,
    required DateTime returnDate,
    required String reason,
    required double returnAmount,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final data = {
        'sale_id': saleId,
        'reason': reason,
        'items': items,
      };

      AppLogger.info('Creating sale return for sale: $saleId');

      return await _apiService.post<SaleReturn>(
        '$_baseUrl/returns',
        body: data,
        fromJson: (data) => SaleReturn.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      AppLogger.error('Error creating sale return', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Approve sale return - matches backend ApproveSaleReturn
  Future<ApiResponse<SaleReturn>> approveSaleReturn(String returnId) async {
    try {
      AppLogger.info('Approving sale return: $returnId');

      return await _apiService.post<SaleReturn>(
        '$_baseUrl/returns/$returnId/approve',
        fromJson: (data) => SaleReturn.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      AppLogger.error('Error approving sale return', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Reject sale return - matches backend RejectSaleReturn
  Future<ApiResponse<void>> rejectSaleReturn(String returnId, String reason) async {
    try {
      AppLogger.info('Rejecting sale return: $returnId');

      return await _apiService.post<void>(
        '$_baseUrl/returns/$returnId/reject',
        body: {'reason': reason},
        fromJson: (_) {},
      );
    } catch (e) {
      AppLogger.error('Error rejecting sale return', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  /// Get pending returns - matches backend GetPendingReturns
  Future<ApiResponse<List<SaleReturn>>> getPendingReturns({String? shopId}) async {
    try {
      final params = <String, dynamic>{};
      if (shopId != null && shopId.isNotEmpty) params['shop_id'] = shopId;

      AppLogger.info('Fetching pending returns');

      return await _apiService.get<List<SaleReturn>>(
        '$_baseUrl/pending/returns',
        queryParams: params,
        fromJson: (data) {
          if (data is List) {
            return data.map((item) => SaleReturn.fromJson(item as Map<String, dynamic>)).toList();
          }
          return [];
        },
      );
    } catch (e) {
      AppLogger.error('Error fetching pending returns', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  // ===== Dashboard & Reports =====

  /// Get dashboard summary - matches backend GetDashboardSummary
  Future<ApiResponse<Map<String, dynamic>>> getDashboardSummary(String? shopId) async {
    try {
      final params = <String, dynamic>{};
      if (shopId != null && shopId.isNotEmpty) params['shop_id'] = shopId;

      AppLogger.info('Fetching dashboard summary');

      return await _apiService.get<Map<String, dynamic>>(
        '$_baseUrl/dashboard/summary',
        queryParams: params,
        fromJson: (data) => data as Map<String, dynamic>,
      );
    } catch (e) {
      AppLogger.error('Error fetching dashboard summary', e);
      return ApiResponse.error(error: e.toString());
    }
  }

  // ===== Utility Methods =====

  /// Validate sale before submission
  bool validateSale(Map<String, dynamic> saleData) {
    try {
      // Check required fields
      if (saleData['shop_id'] == null || saleData['shop_id'].toString().isEmpty) {
        AppLogger.warning('Sale validation failed: shop_id is required');
        return false;
      }

      if (saleData['items'] == null || (saleData['items'] as List).isEmpty) {
        AppLogger.warning('Sale validation failed: items are required');
        return false;
      }

      // Validate each item
      for (var item in saleData['items'] as List) {
        if (item['product_id'] == null || item['quantity'] == null || item['unit_price'] == null) {
          AppLogger.warning('Sale validation failed: invalid item data');
          return false;
        }

        if ((item['quantity'] as int) <= 0) {
          AppLogger.warning('Sale validation failed: quantity must be positive');
          return false;
        }

        if ((item['unit_price'] as double) <= 0) {
          AppLogger.warning('Sale validation failed: unit_price must be positive');
          return false;
        }
      }

      // Validate payment method
      final validPaymentMethods = ['cash', 'card', 'upi', 'credit'];
      final paymentMethod = saleData['payment_method']?.toString().toLowerCase();
      if (paymentMethod != null && !validPaymentMethods.contains(paymentMethod)) {
        AppLogger.warning('Sale validation failed: invalid payment method');
        return false;
      }

      return true;
    } catch (e) {
      AppLogger.error('Error validating sale', e);
      return false;
    }
  }

  /// Calculate sale totals
  Map<String, double> calculateSaleTotals(List<Map<String, dynamic>> items) {
    double subtotal = 0;
    double discount = 0;

    for (var item in items) {
      final quantity = (item['quantity'] as num).toDouble();
      final unitPrice = (item['unit_price'] as num).toDouble();
      final discountAmount = (item['discount_amount'] as num?)?.toDouble() ?? 0;

      subtotal += quantity * unitPrice;
      discount += discountAmount;
    }

    final taxRate = 0.18; // 18% GST
    final taxableAmount = subtotal - discount;
    final tax = taxableAmount * taxRate;
    final total = taxableAmount + tax;

    return {
      'subtotal': subtotal,
      'discount': discount,
      'tax': tax,
      'total': total,
    };
  }
}
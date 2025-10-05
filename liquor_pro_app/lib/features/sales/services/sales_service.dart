import '../../../core/services/api_service.dart';
import '../models/sale.dart';

/// Sales service for all sales-related API operations
class SalesService {
  final ApiService _apiService;

  SalesService(this._apiService);

  // ===== Individual Sales Operations =====

  /// Get all sales with optional filters
  Future<ApiResponse<List<Sale>>> getSales({
    String? shopId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (shopId != null) 'shop_id': shopId,
      if (status != null) 'status': status,
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (endDate != null) 'end_date': endDate.toIso8601String(),
    };

    return await _apiService.get<List<Sale>>(
      '/api/sales/sales',
      queryParameters: params,
      parser: (data) {
        if (data is List) {
          return data.map((item) => Sale.fromJson(item as Map<String, dynamic>)).toList();
        }
        return [];
      },
    );
  }

  /// Get sale by ID
  Future<ApiResponse<Sale>> getSaleById(String saleId) async {
    return await _apiService.get<Sale>(
      '/api/sales/sales/$saleId',
      parser: (data) => Sale.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Create new sale
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
  }) async {
    final data = {
      'shop_id': shopId,
      'salesman_id': salesmanId,
      'sale_date': saleDate.toIso8601String(),
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'items': items,
      'sub_total': subTotal,
      'discount_amount': discountAmount,
      'tax_amount': taxAmount,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'payment_method': paymentMethod,
    };

    return await _apiService.post<Sale>(
      '/api/sales/sales',
      data: data,
      parser: (data) => Sale.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Approve sale
  Future<ApiResponse<Sale>> approveSale(String saleId) async {
    return await _apiService.post<Sale>(
      '/api/sales/sales/$saleId/approve',
      parser: (data) => Sale.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Reject sale
  Future<ApiResponse<Sale>> rejectSale(String saleId, String reason) async {
    return await _apiService.post<Sale>(
      '/api/sales/sales/$saleId/reject',
      data: {'reason': reason},
      parser: (data) => Sale.fromJson(data as Map<String, dynamic>),
    );
  }

  // ===== Daily Sales Records Operations =====

  /// Get daily sales records
  Future<ApiResponse<List<DailySalesRecord>>> getDailySalesRecords({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (shopId != null) 'shop_id': shopId,
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (endDate != null) 'end_date': endDate.toIso8601String(),
      if (status != null) 'status': status,
    };

    return await _apiService.get<List<DailySalesRecord>>(
      '/api/sales/daily-records',
      queryParameters: params,
      parser: (data) {
        if (data is List) {
          return data.map((item) => DailySalesRecord.fromJson(item as Map<String, dynamic>)).toList();
        }
        return [];
      },
    );
  }

  /// Get daily sales record by ID
  Future<ApiResponse<DailySalesRecord>> getDailySalesRecordById(String recordId) async {
    return await _apiService.get<DailySalesRecord>(
      '/api/sales/daily-records/$recordId',
      parser: (data) => DailySalesRecord.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Create daily sales record
  Future<ApiResponse<DailySalesRecord>> createDailySalesRecord({
    required String shopId,
    required DateTime recordDate,
    required double totalSales,
    double totalReturns = 0,
    required int salesCount,
    int returnsCount = 0,
  }) async {
    final data = {
      'shop_id': shopId,
      'record_date': recordDate.toIso8601String(),
      'total_sales': totalSales,
      'total_returns': totalReturns,
      'sales_count': salesCount,
      'returns_count': returnsCount,
    };

    return await _apiService.post<DailySalesRecord>(
      '/api/sales/daily-records',
      data: data,
      parser: (data) => DailySalesRecord.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Approve daily sales record
  Future<ApiResponse<DailySalesRecord>> approveDailySalesRecord(String recordId) async {
    return await _apiService.post<DailySalesRecord>(
      '/api/sales/daily-records/$recordId/approve',
      parser: (data) => DailySalesRecord.fromJson(data as Map<String, dynamic>),
    );
  }

  // ===== Sale Returns Operations =====

  /// Get sale returns
  Future<ApiResponse<List<SaleReturn>>> getSaleReturns({
    String? shopId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (shopId != null) 'shop_id': shopId,
      if (status != null) 'status': status,
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (endDate != null) 'end_date': endDate.toIso8601String(),
    };

    return await _apiService.get<List<SaleReturn>>(
      '/api/sales/returns',
      queryParameters: params,
      parser: (data) {
        if (data is List) {
          return data.map((item) => SaleReturn.fromJson(item as Map<String, dynamic>)).toList();
        }
        return [];
      },
    );
  }

  /// Get sale return by ID
  Future<ApiResponse<SaleReturn>> getSaleReturnById(String returnId) async {
    return await _apiService.get<SaleReturn>(
      '/api/sales/returns/$returnId',
      parser: (data) => SaleReturn.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Create sale return
  Future<ApiResponse<SaleReturn>> createSaleReturn({
    required String saleId,
    required String shopId,
    required DateTime returnDate,
    required String reason,
    required double returnAmount,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = {
      'sale_id': saleId,
      'shop_id': shopId,
      'return_date': returnDate.toIso8601String(),
      'reason': reason,
      'return_amount': returnAmount,
      'items': items,
    };

    return await _apiService.post<SaleReturn>(
      '/api/sales/returns',
      data: data,
      parser: (data) => SaleReturn.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Approve sale return
  Future<ApiResponse<SaleReturn>> approveSaleReturn(String returnId) async {
    return await _apiService.post<SaleReturn>(
      '/api/sales/returns/$returnId/approve',
      parser: (data) => SaleReturn.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Reject sale return
  Future<ApiResponse<SaleReturn>> rejectSaleReturn(String returnId, String reason) async {
    return await _apiService.post<SaleReturn>(
      '/api/sales/returns/$returnId/reject',
      data: {'reason': reason},
      parser: (data) => SaleReturn.fromJson(data as Map<String, dynamic>),
    );
  }

  // ===== Pending Items =====

  /// Get pending sales
  Future<ApiResponse<List<Sale>>> getPendingSales({
    String? shopId,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (shopId != null) 'shop_id': shopId,
    };

    return await _apiService.get<List<Sale>>(
      '/api/sales/pending',
      queryParameters: params,
      parser: (data) {
        if (data is List) {
          return data.map((item) => Sale.fromJson(item as Map<String, dynamic>)).toList();
        }
        return [];
      },
    );
  }

  /// Get pending returns
  Future<ApiResponse<List<SaleReturn>>> getPendingReturns({
    String? shopId,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (shopId != null) 'shop_id': shopId,
    };

    return await _apiService.get<List<SaleReturn>>(
      '/api/sales/returns/pending',
      queryParameters: params,
      parser: (data) {
        if (data is List) {
          return data.map((item) => SaleReturn.fromJson(item as Map<String, dynamic>)).toList();
        }
        return [];
      },
    );
  }

  // ===== Financial Reports =====

  /// Get uncollected sales (sales with due amount)
  Future<ApiResponse<List<Sale>>> getUncollectedSales({
    String? shopId,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (shopId != null) 'shop_id': shopId,
    };

    return await _apiService.get<List<Sale>>(
      '/api/sales/uncollected',
      queryParameters: params,
      parser: (data) {
        if (data is List) {
          return data.map((item) => Sale.fromJson(item as Map<String, dynamic>)).toList();
        }
        return [];
      },
    );
  }
}

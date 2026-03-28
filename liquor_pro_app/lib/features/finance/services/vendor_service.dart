import '../../../core/services/dio_api_service.dart';
import '../../../core/models/api_response.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/safe_casting.dart';
import '../models/vendor_model.dart';

/// Vendor Service - Handles all vendor-related API calls
///
/// Provides comprehensive vendor management functionality including:
/// - CRUD operations for vendors
/// - Transaction history (purchases/payments)
/// - Payment recording
/// - Bank account management
class VendorService {
  final DioApiService _apiService;

  VendorService(this._apiService);

  /// List all vendors with financial summary
  Future<ApiResponse<List<Vendor>>> getVendors({
    bool includeInactive = false,
    bool forceRefresh = false,
  }) async {
    try {
      Logger.debug('[VendorService] Fetching vendors (includeInactive: $includeInactive, forceRefresh: $forceRefresh)');

      final queryParams = <String, dynamic>{
        if (includeInactive) 'include_inactive': 'true',
      };

      // Add cache-busting parameter if force refresh requested
      if (forceRefresh) {
        queryParams['_t'] = DateTime.now().millisecondsSinceEpoch.toString();
      }

      final response = await _apiService.get(
        '/api/finance/vendors',
        queryParams: queryParams,
      );

      Logger.debug('[VendorService] Response - Success: ${response.success}');
      Logger.debug('[VendorService] Response data type: ${response.data.runtimeType}');

      if (response.success && response.data != null) {
        // Handle both List and Map responses
        List<dynamic> vendorList;

        if (response.data is List) {
          vendorList = SafeCast.toList<dynamic>(response.data);
        } else if (response.data is Map) {
          // Backend might wrap data in { "vendors": [...] } or { "data": [...] }
          final dataMap = SafeCast.toMap<String, dynamic>(response.data);
          vendorList = SafeCast.toList<dynamic>(dataMap['vendors'] ?? dataMap['data'] ?? []);
        } else {
          Logger.error('[VendorService] Unexpected response data type');
          return ApiResponse.error(error: 'Invalid response format');
        }

        final vendors = vendorList
            .map((json) => Vendor.fromJson(SafeCast.toMap<String, dynamic>(json)))
            .toList();

        Logger.info('[VendorService] Loaded ${vendors.length} vendors');
        return ApiResponse.success(vendors);
      }

      Logger.error('[VendorService] Failed: ${response.error}');
      return ApiResponse.error(error: response.error ?? 'Failed to load vendors');
    } catch (e, stackTrace) {
      Logger.error('[VendorService] Exception: $e');
      Logger.error('[VendorService] Stack trace: $stackTrace');
      return ApiResponse.error(error: 'Error loading vendors: $e');
    }
  }

  /// Create a new vendor
  Future<ApiResponse<Vendor>> createVendor(VendorRequest request) async {
    try {
      Logger.debug('[VendorService] Creating vendor: ${request.name}');

      final response = await _apiService.post(
        '/api/finance/vendors',
        body: request.toJson(),
      );

      Logger.debug('[VendorService] Response - Success: ${response.success}');

      if (response.success && response.data != null) {
        final vendor = Vendor.fromJson(SafeCast.toMap<String, dynamic>(response.data));
        Logger.info('[VendorService] Vendor created successfully - ID: ${vendor.id}');
        return ApiResponse.success(vendor);
      }

      Logger.error('[VendorService] Failed: ${response.error}');
      return ApiResponse.error(error: response.error ?? 'Failed to create vendor');
    } catch (e, stackTrace) {
      Logger.error('[VendorService] Exception: $e');
      Logger.error('[VendorService] Stack trace: $stackTrace');
      return ApiResponse.error(error: 'Error creating vendor: $e');
    }
  }

  /// Update an existing vendor
  Future<ApiResponse<Vendor>> updateVendor(
    String id,
    VendorRequest request,
  ) async {
    try {
      Logger.debug('[VendorService] Updating vendor: $id');

      final response = await _apiService.put(
        '/api/finance/vendors/$id',
        body: request.toJson(),
      );

      Logger.debug('[VendorService] Response - Success: ${response.success}');

      if (response.success && response.data != null) {
        final vendor = Vendor.fromJson(SafeCast.toMap<String, dynamic>(response.data));
        Logger.info('[VendorService] Vendor updated successfully');
        return ApiResponse.success(vendor);
      }

      Logger.error('[VendorService] Failed: ${response.error}');
      return ApiResponse.error(error: response.error ?? 'Failed to update vendor');
    } catch (e, stackTrace) {
      Logger.error('[VendorService] Exception: $e');
      Logger.error('[VendorService] Stack trace: $stackTrace');
      return ApiResponse.error(error: 'Error updating vendor: $e');
    }
  }

  /// Delete a vendor
  Future<ApiResponse<void>> deleteVendor(String id) async {
    try {
      Logger.debug('[VendorService] Deleting vendor: $id');

      final response = await _apiService.delete('/api/finance/vendors/$id');

      Logger.debug('[VendorService] Response - Success: ${response.success}');

      if (response.success) {
        Logger.info('[VendorService] Vendor deleted successfully');
        return ApiResponse.success(null);
      }

      Logger.error('[VendorService] Failed: ${response.error}');
      return ApiResponse.error(error: response.error ?? 'Failed to delete vendor');
    } catch (e, stackTrace) {
      Logger.error('[VendorService] Exception: $e');
      Logger.error('[VendorService] Stack trace: $stackTrace');
      return ApiResponse.error(error: 'Error deleting vendor: $e');
    }
  }

  /// Get vendor details by ID
  Future<ApiResponse<Vendor>> getVendorById(String id) async {
    try {
      Logger.debug('[VendorService] Fetching vendor details: $id');

      final response = await _apiService.get('/api/finance/vendors/$id');

      Logger.debug('[VendorService] Response - Success: ${response.success}');

      if (response.success && response.data != null) {
        final vendor = Vendor.fromJson(SafeCast.toMap<String, dynamic>(response.data));
        Logger.info('[VendorService] Vendor details loaded: ${vendor.name}');
        return ApiResponse.success(vendor);
      }

      Logger.error('[VendorService] Failed: ${response.error}');
      return ApiResponse.error(error: response.error ?? 'Failed to load vendor');
    } catch (e, stackTrace) {
      Logger.error('[VendorService] Exception: $e');
      Logger.error('[VendorService] Stack trace: $stackTrace');
      return ApiResponse.error(error: 'Error loading vendor: $e');
    }
  }

  /// Get vendor transaction history
  ///
  /// Returns empty list gracefully if endpoint doesn't exist (404)
  /// or any other error occurs - graceful degradation pattern
  Future<ApiResponse<List<VendorTransaction>>> getVendorTransactions(
    String vendorId, {
    int page = 1,
    int limit = 50,
  }) async {
    try {
      Logger.debug('[VendorService] Fetching transactions for vendor: $vendorId');

      final response = await _apiService.get(
        '/api/finance/vendors/$vendorId/transactions',
        queryParams: {
          'page': page.toString(),
          'limit': limit.toString(),
        },
      );

      // Handle 404 gracefully - endpoint may not exist yet
      if (!response.success) {
        // Return empty list instead of error for 404/missing endpoint
        Logger.info('[VendorService] Transactions not available yet (endpoint may not exist)');
        return ApiResponse.success([]);
      }

      if (response.data != null) {
        // Handle both List and Map responses
        List<dynamic> transactionList;

        if (response.data is List) {
          transactionList = SafeCast.toList<dynamic>(response.data);
        } else if (response.data is Map) {
          final dataMap = SafeCast.toMap<String, dynamic>(response.data);
          transactionList = SafeCast.toList<dynamic>(dataMap['transactions'] ?? dataMap['data'] ?? []);
        } else {
          return ApiResponse.success([]);
        }

        final transactions = transactionList
            .map((json) =>
                VendorTransaction.fromJson(SafeCast.toMap<String, dynamic>(json)))
            .toList();

        Logger.info('[VendorService] Loaded ${transactions.length} transactions');
        return ApiResponse.success(transactions);
      }

      return ApiResponse.success([]);
    } catch (e) {
      // Return empty list on any error - graceful degradation
      Logger.error('[VendorService] Could not load transactions: $e');
      return ApiResponse.success([]);
    }
  }

  /// Record payment to vendor
  Future<ApiResponse<VendorTransaction>> recordPayment({
    required String vendorId,
    required double amount,
    required String paymentMethod,
    String? referenceNo,
    String? description,
  }) async {
    try {
      Logger.debug('[VendorService] Recording payment to vendor: $vendorId');
      Logger.debug('[VendorService] Amount: ₹$amount, Method: $paymentMethod');

      final request = VendorTransactionRequest(
        vendorId: vendorId,
        transactionType: 'payment',
        amount: amount,
        description: description ?? 'Payment to vendor',
        referenceNo: referenceNo,
        paymentMethod: paymentMethod,
      );

      final response = await _apiService.post(
        '/api/finance/vendors/transactions',
        body: request.toJson(),
      );

      Logger.debug('[VendorService] Response - Success: ${response.success}');

      if (response.success && response.data != null) {
        final transaction =
            VendorTransaction.fromJson(SafeCast.toMap<String, dynamic>(response.data));
        Logger.info('[VendorService] Payment recorded successfully');
        return ApiResponse.success(transaction);
      }

      Logger.error('[VendorService] Failed: ${response.error}');
      return ApiResponse.error(error: response.error ?? 'Failed to record payment');
    } catch (e, stackTrace) {
      Logger.error('[VendorService] Exception: $e');
      Logger.error('[VendorService] Stack trace: $stackTrace');
      return ApiResponse.error(error: 'Error recording payment: $e');
    }
  }

  /// Add bank account to vendor
  Future<ApiResponse<VendorBankAccount>> addBankAccount(
    String vendorId,
    VendorBankAccountRequest request,
  ) async {
    try {
      Logger.debug('[VendorService] Adding bank account to vendor: $vendorId');
      Logger.debug('[VendorService] Bank: ${request.bankName}');

      final response = await _apiService.post(
        '/api/finance/vendors/$vendorId/bank-accounts',
        body: request.toJson(),
      );

      Logger.debug('[VendorService] Response - Success: ${response.success}');

      if (response.success && response.data != null) {
        final bankAccount =
            VendorBankAccount.fromJson(SafeCast.toMap<String, dynamic>(response.data));
        Logger.info('[VendorService] Bank account added successfully');
        return ApiResponse.success(bankAccount);
      }

      Logger.error('[VendorService] Failed: ${response.error}');
      return ApiResponse.error(
          error: response.error ?? 'Failed to add bank account');
    } catch (e, stackTrace) {
      Logger.error('[VendorService] Exception: $e');
      Logger.error('[VendorService] Stack trace: $stackTrace');
      return ApiResponse.error(error: 'Error adding bank account: $e');
    }
  }

  /// Get vendors with outstanding balance (for quick payment access)
  Future<ApiResponse<List<Vendor>>> getVendorsWithOutstanding() async {
    try {
      Logger.debug('[VendorService] Fetching vendors with outstanding balance');

      final response = await getVendors();

      if (response.success && response.data != null) {
        final vendorsWithOutstanding = response.data!
            .where((vendor) => vendor.outstandingBalance > 0)
            .toList()
          ..sort((a, b) => b.outstandingBalance.compareTo(a.outstandingBalance));

        Logger.info(
            '[VendorService] Found ${vendorsWithOutstanding.length} vendors with outstanding balance');
        return ApiResponse.success(vendorsWithOutstanding);
      }

      return response;
    } catch (e, stackTrace) {
      Logger.error('[VendorService] Exception: $e');
      Logger.error('[VendorService] Stack trace: $stackTrace');
      return ApiResponse.error(error: 'Error filtering vendors: $e');
    }
  }

  /// Search vendors by name
  Future<ApiResponse<List<Vendor>>> searchVendors(String query) async {
    try {
      Logger.debug('[VendorService] Searching vendors: "$query"');

      final response = await getVendors();

      if (response.success && response.data != null) {
        final searchResults = response.data!
            .where((vendor) =>
                vendor.name.toLowerCase().contains(query.toLowerCase()) ||
                (vendor.contactPerson?.toLowerCase().contains(query.toLowerCase()) ?? false) ||
                (vendor.phone?.contains(query) ?? false))
            .toList();

        Logger.info('[VendorService] Found ${searchResults.length} matching vendors');
        return ApiResponse.success(searchResults);
      }

      return response;
    } catch (e, stackTrace) {
      Logger.error('[VendorService] Exception: $e');
      Logger.error('[VendorService] Stack trace: $stackTrace');
      return ApiResponse.error(error: 'Error searching vendors: $e');
    }
  }
}

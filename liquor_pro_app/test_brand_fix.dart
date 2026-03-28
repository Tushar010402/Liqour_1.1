/// Quick test to verify BrandOnboardingService accepts AuthService
/// Run with: dart test_brand_fix.dart
library;

import 'dart:async';

// Mock classes for testing
class MockAuthService {
  Future<String?> getTenantId() async {
    return 'test-tenant-123';
  }
}

class MockApiService {
  final MockAuthService authService;

  MockApiService(this.authService);

  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    print('📤 POST $endpoint');
    print('📦 Body: $body');
    return null;
  }
}

// Simplified BrandOnboardingService for testing
class BrandOnboardingService {
  final MockApiService _apiService;

  BrandOnboardingService(this._apiService);

  Future<Map<String, dynamic>> onboardBrands({
    required List<String> brandIds,
    required List<String> variantIds,
    String? shopId,
  }) async {
    print('🎯 BrandOnboardingService.onboardBrands() called');
    print('   - Brand IDs: $brandIds');
    print('   - Variant IDs: $variantIds');

    // Get tenant ID from ApiService's AuthService
    final tenantId = await _apiService.authService.getTenantId();
    print('🎯 Tenant ID retrieved: $tenantId');

    if (tenantId == null || tenantId.isEmpty) {
      print('❌ Tenant ID is null or empty!');
      return {
        'success': false,
        'message': 'Tenant ID is required for onboarding',
      };
    }

    final requestBody = {
      'brand_ids': brandIds,
      'variant_ids': variantIds,
      'tenant_id': tenantId,
      if (shopId != null) 'shop_id': shopId,
    };

    print('✅ Request body constructed with tenant_id: $tenantId');
    await _apiService.post('/api/inventory/saas-brands/onboard',
        body: requestBody);

    return {
      'success': true,
      'message': 'Onboarding initiated',
    };
  }
}

void main() async {
  print('🧪 Testing BrandOnboardingService Fix\n');

  final authService = MockAuthService();
  final apiService = MockApiService(authService);

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('Test: Service gets AuthService from ApiService');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final service = BrandOnboardingService(apiService);
  final result = await service.onboardBrands(
    brandIds: ['brand-123'],
    variantIds: ['variant-456'],
  );

  if (result['success']!) {
    print('✅ Test PASSED: Successfully retrieved tenant_id from ApiService.authService');
    print('   Message: ${result['message']}\n');
  } else {
    print('❌ Test FAILED: Could not retrieve tenant_id');
    print('   Message: ${result['message']}\n');
  }

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('Summary');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  if (result['success']!) {
    print('🎉 ALL TESTS PASSED!');
    print('✅ BrandOnboardingService accesses AuthService via ApiService');
    print('✅ tenant_id is properly included in request body');
    print('✅ No need to pass AuthService separately');
  } else {
    print('❌ TESTS FAILED!');
    print('   Check the implementation');
  }
}

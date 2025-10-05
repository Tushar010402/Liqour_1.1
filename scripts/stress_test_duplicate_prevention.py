#!/usr/bin/env python3
"""
Stress Test for Duplicate Prevention System
File: scripts/stress_test_duplicate_prevention.py
Purpose: Test duplicate prevention under extreme concurrent load
"""

import asyncio
import aiohttp
import time
import statistics
from typing import List, Dict, Tuple
import json
from datetime import datetime
import sys

# Configuration
INVENTORY_URL = "http://localhost:8093"
AUTH_URL = "http://localhost:8091"
TEST_PHONE = "+918630668489"
TENANT_ID = "373e965a-6dec-44d6-a2ab-0400449fc71d"
CONCURRENT_REQUESTS = 50
TEST_ITERATIONS = 100

class Colors:
    BLUE = '\033[0;34m'
    GREEN = '\033[0;32m'
    RED = '\033[0;31m'
    YELLOW = '\033[1;33m'
    NC = '\033[0m'

class LoadTester:
    def __init__(self):
        self.auth_token = None
        self.results = []
        self.brand_ids = []

    async def authenticate(self, session: aiohttp.ClientSession) -> bool:
        """Authenticate and get token"""
        try:
            # Send OTP
            async with session.post(
                f"{AUTH_URL}/api/auth/send-otp",
                json={"mobile_number": TEST_PHONE},
                timeout=aiohttp.ClientTimeout(total=10)
            ) as response:
                if response.status != 200:
                    print(f"{Colors.RED}✗{Colors.NC} Failed to send OTP: {response.status}")
                    return False

            await asyncio.sleep(2)

            # Verify OTP
            async with session.post(
                f"{AUTH_URL}/api/auth/verify-otp",
                json={"mobile_number": TEST_PHONE, "otp": "000000"},
                timeout=aiohttp.ClientTimeout(total=10)
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    self.auth_token = data.get('token')
                    if self.auth_token:
                        print(f"{Colors.GREEN}✓{Colors.NC} Authenticated successfully")
                        return True

                print(f"{Colors.RED}✗{Colors.NC} Failed to authenticate")
                return False

        except Exception as e:
            print(f"{Colors.RED}✗{Colors.NC} Authentication error: {e}")
            return False

    async def get_brand_ids(self, session: aiohttp.ClientSession) -> List[str]:
        """Fetch available brand IDs"""
        try:
            headers = {
                "Authorization": f"Bearer {self.auth_token}",
                "X-Tenant-ID": TENANT_ID
            }

            async with session.get(
                f"{INVENTORY_URL}/api/inventory/saas-brands/available",
                headers=headers,
                timeout=aiohttp.ClientTimeout(total=10)
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    if 'data' in data and len(data['data']) > 0:
                        brand_ids = [brand['id'] for brand in data['data'][:3]]
                        print(f"{Colors.GREEN}✓{Colors.NC} Retrieved {len(brand_ids)} brand IDs")
                        return brand_ids

                print(f"{Colors.RED}✗{Colors.NC} Failed to fetch brands: {response.status}")
                return []

        except Exception as e:
            print(f"{Colors.RED}✗{Colors.NC} Error fetching brands: {e}")
            return []

    async def onboard_brand(
        self,
        session: aiohttp.ClientSession,
        brand_ids: List[str],
        thread_id: int
    ) -> Dict:
        """Attempt to onboard a brand"""
        start_time = time.time()

        headers = {
            "Authorization": f"Bearer {self.auth_token}",
            "X-Tenant-ID": TENANT_ID,
            "Content-Type": "application/json"
        }

        payload = {
            "brand_ids": brand_ids,
            "shop_id": "00000000-0000-0000-0000-000000000001"
        }

        try:
            async with session.post(
                f"{INVENTORY_URL}/api/inventory/saas-brands/onboard",
                headers=headers,
                json=payload,
                timeout=aiohttp.ClientTimeout(total=30)
            ) as response:
                end_time = time.time()
                response_time = (end_time - start_time) * 1000  # Convert to ms

                if response.status == 200:
                    data = await response.json()
                    products_created = data.get('onboarded_products', 0)

                    return {
                        'thread_id': thread_id,
                        'status': 'success',
                        'http_code': response.status,
                        'response_time': response_time,
                        'products_created': products_created,
                        'timestamp': datetime.now().isoformat()
                    }
                else:
                    body = await response.text()
                    return {
                        'thread_id': thread_id,
                        'status': 'failure',
                        'http_code': response.status,
                        'response_time': response_time,
                        'products_created': 0,
                        'error': body[:100],
                        'timestamp': datetime.now().isoformat()
                    }

        except asyncio.TimeoutError:
            end_time = time.time()
            return {
                'thread_id': thread_id,
                'status': 'timeout',
                'http_code': 0,
                'response_time': (end_time - start_time) * 1000,
                'products_created': 0,
                'error': 'Request timeout',
                'timestamp': datetime.now().isoformat()
            }
        except Exception as e:
            end_time = time.time()
            return {
                'thread_id': thread_id,
                'status': 'error',
                'http_code': 0,
                'response_time': (end_time - start_time) * 1000,
                'products_created': 0,
                'error': str(e)[:100],
                'timestamp': datetime.now().isoformat()
            }

    async def run_concurrent_test(self, session: aiohttp.ClientSession):
        """Run concurrent onboarding test"""
        print(f"\n{Colors.BLUE}[TEST]{Colors.NC} Running {CONCURRENT_REQUESTS} concurrent onboarding requests...")
        print(f"{Colors.BLUE}[TEST]{Colors.NC} Target: Same brand (duplicate prevention test)")

        # Use only first brand for duplicate testing
        test_brand_ids = [self.brand_ids[0]]

        # Create concurrent tasks
        tasks = [
            self.onboard_brand(session, test_brand_ids, i)
            for i in range(CONCURRENT_REQUESTS)
        ]

        # Execute all tasks concurrently
        results = await asyncio.gather(*tasks)
        self.results.extend(results)

        return results

    async def run_sequential_test(self, session: aiohttp.ClientSession):
        """Run sequential onboarding test"""
        print(f"\n{Colors.BLUE}[TEST]{Colors.NC} Running sequential onboarding test...")

        results = []
        for i in range(10):
            result = await self.onboard_brand(session, [self.brand_ids[0]], i)
            results.append(result)
            await asyncio.sleep(0.5)  # Small delay

        self.results.extend(results)
        return results

    def analyze_results(self, results: List[Dict]):
        """Analyze test results"""
        if not results:
            print(f"{Colors.RED}✗{Colors.NC} No results to analyze")
            return

        total_requests = len(results)
        successful = sum(1 for r in results if r['status'] == 'success')
        failed = sum(1 for r in results if r['status'] != 'success')

        response_times = [r['response_time'] for r in results if r['response_time'] > 0]
        products_created = [r['products_created'] for r in results]
        total_products = sum(products_created)
        requests_with_products = sum(1 for p in products_created if p > 0)

        print(f"\n{'='*60}")
        print(f"{Colors.BLUE}DUPLICATE PREVENTION STRESS TEST RESULTS{Colors.NC}")
        print(f"{'='*60}")
        print(f"Total Requests:          {total_requests}")
        print(f"Successful:              {successful} ({successful/total_requests*100:.1f}%)")
        print(f"Failed:                  {failed} ({failed/total_requests*100:.1f}%)")

        if response_times:
            print(f"\nResponse Times (ms):")
            print(f"  Average:               {statistics.mean(response_times):.2f}")
            print(f"  Min:                   {min(response_times):.2f}")
            print(f"  Max:                   {max(response_times):.2f}")
            print(f"  P95:                   {sorted(response_times)[int(len(response_times)*0.95)]:.2f}")
            print(f"  P99:                   {sorted(response_times)[int(len(response_times)*0.99)]:.2f}")

        print(f"\nDuplicate Prevention:")
        print(f"  Total Products Created: {total_products}")
        print(f"  Requests Creating Products: {requests_with_products}")

        # Duplicate prevention effectiveness
        if requests_with_products == 1:
            print(f"  {Colors.GREEN}✓ PASS{Colors.NC} - Only 1 request created products (duplicate prevention working)")
        elif requests_with_products == 0:
            print(f"  {Colors.YELLOW}⚠ INFO{Colors.NC} - No products created (brand may already exist)")
        else:
            print(f"  {Colors.RED}✗ FAIL{Colors.NC} - Multiple requests created products (duplicate prevention FAILED)")
            print(f"  {Colors.RED}⚠ CRITICAL{Colors.NC} - Database duplicates may exist!")

        print(f"{'='*60}\n")

        # Performance warnings
        if response_times:
            avg_time = statistics.mean(response_times)
            if avg_time > 500:
                print(f"{Colors.YELLOW}⚠{Colors.NC} Warning: Average response time ({avg_time:.2f}ms) exceeds 500ms")

            p95_time = sorted(response_times)[int(len(response_times)*0.95)]
            if p95_time > 2000:
                print(f"{Colors.YELLOW}⚠{Colors.NC} Warning: P95 response time ({p95_time:.2f}ms) exceeds 2s")

        if failed/total_requests > 0.05:
            print(f"{Colors.YELLOW}⚠{Colors.NC} Warning: Error rate ({failed/total_requests*100:.1f}%) exceeds 5%")

    def save_results(self):
        """Save results to JSON file"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"results/stress_test_{timestamp}.json"

        with open(filename, 'w') as f:
            json.dump({
                'test_config': {
                    'concurrent_requests': CONCURRENT_REQUESTS,
                    'tenant_id': TENANT_ID,
                    'timestamp': timestamp
                },
                'results': self.results
            }, f, indent=2)

        print(f"{Colors.GREEN}✓{Colors.NC} Results saved to {filename}")

    async def run_tests(self):
        """Main test runner"""
        async with aiohttp.ClientSession() as session:
            # Authenticate
            if not await self.authenticate(session):
                return False

            # Get brand IDs
            self.brand_ids = await self.get_brand_ids(session)
            if not self.brand_ids:
                return False

            # Test 1: Concurrent duplicate prevention
            results1 = await self.run_concurrent_test(session)
            self.analyze_results(results1)

            # Wait between tests
            await asyncio.sleep(2)

            # Test 2: Sequential test
            results2 = await self.run_sequential_test(session)
            print(f"\n{Colors.BLUE}Sequential Test Results:{Colors.NC}")
            self.analyze_results(results2)

            # Save all results
            self.save_results()

            return True

async def main():
    """Entry point"""
    print(f"{Colors.BLUE}Brand Onboarding Duplicate Prevention Stress Test{Colors.NC}")
    print(f"{Colors.BLUE}{'='*60}{Colors.NC}\n")

    # Create results directory
    import os
    os.makedirs('results', exist_ok=True)

    tester = LoadTester()
    success = await tester.run_tests()

    if not success:
        print(f"\n{Colors.RED}✗{Colors.NC} Tests failed to complete")
        sys.exit(1)

    print(f"\n{Colors.GREEN}✓{Colors.NC} All tests completed successfully")

    # Recommendations
    print(f"\n{Colors.BLUE}Next Steps:{Colors.NC}")
    print("1. Verify database for duplicates:")
    print("   psql -c \"SELECT saas_variant_id, COUNT(*) FROM products")
    print("            WHERE saas_variant_id IS NOT NULL")
    print("            GROUP BY tenant_id, saas_variant_id")
    print("            HAVING COUNT(*) > 1;\"")
    print("\n2. Check detailed results in results/ directory")
    print("3. Review Prometheus metrics for performance trends")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}⚠{Colors.NC} Test interrupted by user")
        sys.exit(1)

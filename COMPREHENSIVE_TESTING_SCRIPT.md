# 🧪 LiquorPro Backend-Frontend Integration Testing Script

## Overview
This comprehensive testing script validates 100% backend-frontend integration for the LiquorPro management system. It covers all user roles, permissions, API endpoints, and critical business flows.

---

## 📋 User Roles & Access Rights Analysis

### Role Hierarchy & Permissions

#### 1. **saas_admin** (Super Administrator)
- **Scope**: Global system access across all tenants
- **Permissions**:
  - Create/manage tenants
  - Global user management
  - System statistics and health monitoring
  - All admin, manager, and lower role permissions
- **Restricted Endpoints**: `/api/saas-admin/*`

#### 2. **admin** (Tenant Administrator)
- **Scope**: Full tenant-level access
- **Permissions**:
  - User management (create, read, update, delete users)
  - Shop management 
  - Salesman management
  - All manager, executive, assistant_manager, and salesman permissions
- **Key Endpoints**: `/api/admin/*`, all business operations

#### 3. **manager** (Tenant Manager)
- **Scope**: Business operations management
- **Permissions**:
  - Approve/reject sales, returns, expenses
  - Vendor management
  - View pending items
  - Create expenses, daily records
  - All executive, assistant_manager, and salesman permissions
- **Cannot**: Delete users (admin only), delete vendors (admin only)

#### 4. **executive** (Financial Executive)
- **Scope**: Financial oversight
- **Permissions**:
  - View uncollected sales
  - Financial reports access
  - Money collection approvals
  - View operations (no create/modify)

#### 5. **assistant_manager** (Assistant Manager)
- **Scope**: Money collection operations
- **Permissions**:
  - Submit money collections (15-minute approval deadline)
  - Create sales, daily records
  - All salesman permissions
- **Critical**: 15-minute money collection approval workflow

#### 6. **salesman** (Default Role)
- **Scope**: Basic sales operations
- **Permissions**:
  - Create daily sales records
  - Create individual sales
  - Create sale returns
  - Create expenses
  - View own data

---

## 🔧 Testing Environment Setup

### Prerequisites
```bash
# 1. Ensure Docker services are running
docker-compose up -d

# 2. Verify all services are healthy
docker ps
# Expected: gateway:8090, auth:8091, sales:8092, inventory:8093, finance:8094

# 3. Check service health
curl http://localhost:8090/health  # Gateway
curl http://localhost:8091/health  # Auth
curl http://localhost:8092/health  # Sales
curl http://localhost:8093/health  # Inventory
curl http://localhost:8094/health  # Finance
```

### Test Data Setup
```bash
# Database should have:
# - Test tenants
# - Users with different roles
# - Products, categories, brands
# - Sample sales data
# - Expense categories
```

---

## 🧪 Backend API Testing Script

### Phase 1: Authentication & User Management

#### Test 1.1: User Registration & Multi-Tenant Setup
```bash
# Register Admin User (Creates Tenant)
curl -X POST http://localhost:8091/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_admin",
    "email": "admin@test.com", 
    "password": "AdminPass123!",
    "first_name": "Test",
    "last_name": "Admin",
    "phone": "+1234567890",
    "tenant_name": "Test Store",
    "company_name": "Test Store LLC",
    "role": "admin"
  }'

# Expected: 200 OK with token, user, tenant data
```

#### Test 1.2: Role-Based Login Flow
```bash
# Admin Login
curl -X POST http://localhost:8091/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_admin",
    "password": "AdminPass123!"
  }'

# Save admin token for subsequent tests
ADMIN_TOKEN="eyJhbGc..."
```

#### Test 1.3: User Creation by Admin
```bash
# Create Manager User
curl -X POST http://localhost:8091/api/admin/users \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_manager",
    "email": "manager@test.com",
    "password": "ManagerPass123!",
    "first_name": "Test", 
    "last_name": "Manager",
    "phone": "+1234567891",
    "role": "manager"
  }'

# Create Salesman User
curl -X POST http://localhost:8091/api/admin/users \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_salesman", 
    "email": "salesman@test.com",
    "password": "SalesmanPass123!",
    "first_name": "Test",
    "last_name": "Salesman", 
    "phone": "+1234567892",
    "role": "salesman"
  }'

# Expected: 200 OK for each user creation
```

### Phase 2: Inventory Management Testing

#### Test 2.1: Product Catalog Setup (Admin/Manager Only)
```bash
# Create Brand
curl -X POST http://localhost:8093/api/inventory/brands \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Brand",
    "description": "Test brand description"
  }'

# Create Category
curl -X POST http://localhost:8093/api/inventory/categories \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Whiskey",
    "description": "Whiskey products"
  }'

# Create Product
curl -X POST http://localhost:8093/api/inventory/products \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Whiskey 750ml",
    "sku": "TWH750001",
    "brand_id": "brand_uuid_here",
    "category_id": "category_uuid_here",
    "cost_price": 800.00,
    "selling_price": 1200.00,
    "mrp": 1300.00,
    "description": "Premium test whiskey"
  }'

# Expected: 200 OK with product data
```

#### Test 2.2: Permission Testing
```bash
# Login as Salesman
curl -X POST http://localhost:8091/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_salesman",
    "password": "SalesmanPass123!"
  }'

SALESMAN_TOKEN="eyJhbGc..."

# Try to create product (Should FAIL - Forbidden)
curl -X POST http://localhost:8093/api/inventory/products \
  -H "Authorization: Bearer $SALESMAN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Unauthorized Product",
    "sku": "UNAUTH001"
  }'

# Expected: 403 Forbidden
```

### Phase 3: Sales Operations Testing

#### Test 3.1: Daily Sales Record Creation
```bash
# Create Daily Sales Record (Salesman)
curl -X POST http://localhost:8092/api/daily-records \
  -H "Authorization: Bearer $SALESMAN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "record_date": "2025-01-15",
    "shop_id": "shop_uuid_here",
    "total_sales_amount": 15000.00,
    "total_cash_amount": 8000.00,
    "total_card_amount": 4000.00, 
    "total_upi_amount": 2000.00,
    "total_credit_amount": 1000.00,
    "items": [
      {
        "product_id": "product_uuid_here",
        "quantity": 10,
        "unit_price": 1200.00,
        "total_amount": 12000.00,
        "cash_amount": 7000.00,
        "card_amount": 3000.00,
        "upi_amount": 2000.00
      }
    ]
  }'

# Expected: 200 OK with daily record data
```

#### Test 3.2: Approval Workflow Testing
```bash
# Manager Login
curl -X POST http://localhost:8091/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_manager",
    "password": "ManagerPass123!"
  }'

MANAGER_TOKEN="eyJhbGc..."

# Get Pending Sales
curl -X GET http://localhost:8092/api/pending/sales \
  -H "Authorization: Bearer $MANAGER_TOKEN"

# Approve Daily Sales Record
curl -X POST http://localhost:8092/api/daily-records/{record_id}/approve \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "approval_notes": "Record approved - all items verified"
  }'

# Expected: 200 OK with approval confirmation
```

### Phase 4: Financial Operations Testing

#### Test 4.1: Assistant Manager Money Collection (Critical 15-min Flow)
```bash
# Create Assistant Manager
curl -X POST http://localhost:8091/api/admin/users \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_assistant",
    "email": "assistant@test.com", 
    "password": "AssistantPass123!",
    "first_name": "Test",
    "last_name": "Assistant",
    "phone": "+1234567893",
    "role": "assistant_manager"
  }'

# Assistant Manager Login
curl -X POST http://localhost:8091/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_assistant",
    "password": "AssistantPass123!"
  }'

ASSISTANT_TOKEN="eyJhbGc..."

# Submit Money Collection (15-minute deadline starts)
curl -X POST http://localhost:8094/api/assistant-manager/money-collections \
  -H "Authorization: Bearer $ASSISTANT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "executive_id": "executive_uuid_here",
    "shop_id": "shop_uuid_here",
    "amount": 25000.00,
    "collection_type": "daily_sales",
    "description": "Daily sales collection for Shop A",
    "collected_at": "2025-01-15T10:30:00Z"
  }'

# Expected: 200 OK with collection ID and 15-minute deadline
```

#### Test 4.2: Money Collection Approval (Time-Critical)
```bash
# Manager Approval (within 15 minutes)
curl -X POST http://localhost:8094/api/assistant-manager/money-collections/{collection_id}/approve \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "approval_notes": "Collection verified and approved"
  }'

# Expected: 200 OK with approval confirmation
```

### Phase 5: Dashboard & Analytics Testing

#### Test 5.1: Sales Dashboard Data
```bash
# Get Dashboard Summary
curl -X GET http://localhost:8092/api/dashboard/summary \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Expected Response:
{
  "todays_sales": {
    "total_sales": 5,
    "total_amount": 45000.00,
    "approved_sales": 3,
    "approved_amount": 35000.00,
    "pending_sales": 2,
    "pending_amount": 10000.00
  },
  "todays_returns": {
    "total_returns": 1,
    "total_amount": 1200.00,
    "approved_returns": 0,
    "pending_returns": 1
  },
  "pending_sales": 2,
  "pending_returns": 1,
  "total_revenue": 245000.00,
  "total_due": 15000.00,
  "cash_amount": 180000.00,
  "card_amount": 45000.00,
  "upi_amount": 20000.00,
  "credit_amount": 15000.00,
  "shop_summaries": [...],
  "top_products": [...],
  "recent_sales": [...]
}
```

---

## 📱 Flutter Frontend Integration Testing

### Phase 1: Authentication Integration

#### Test F1.1: Login Flow
```dart
// Test Case: OTP-based Login
1. Enter mobile number: +1234567890
2. Verify check-user API call: GET /api/auth/check-user
3. If user exists: Send OTP via /api/auth/send-otp
4. Enter OTP: 000000 (development)
5. Verify OTP via /api/auth/verify-otp
6. Confirm token storage and navigation to home

// Expected Results:
- User redirected to home screen
- Auth state updated with user data
- JWT token stored securely
```

#### Test F1.2: Registration Flow
```dart
// Test Case: New User Registration
1. Enter non-existing mobile number
2. Verify redirect to registration screen
3. Fill registration form with tenant details
4. Submit registration via /api/auth/register
5. Confirm automatic login and home navigation

// Expected Results:
- New tenant and user created
- Automatic login after registration
- Admin role assigned to first user
```

### Phase 2: Home Dashboard Integration

#### Test F2.1: Real-Time Dashboard Data
```dart
// Test Case: Dashboard Service Integration
1. Launch app and login
2. Verify dashboard data loading from /api/sales/dashboard/summary
3. Check real-time stats display:
   - Today's sales amount and count
   - Pending approvals with actual numbers
   - Monthly revenue with proper formatting
   - Outstanding dues with urgency indicators
4. Test pull-to-refresh functionality
5. Verify error handling when backend unavailable

// Expected Results:
- Live data from backend displayed
- Proper number formatting (K/L notation)
- Refresh functionality working
- Error states handled gracefully
```

#### Test F2.2: Navigation & Quick Actions
```dart
// Test Case: Quick Action Integration
1. Verify all quick action buttons functional
2. Test navigation to respective screens
3. Check role-based action availability
4. Test notification badge for pending items
5. Verify deep links to approval screens

// Expected Results:
- All buttons navigate correctly
- Role-based actions enforced
- Notification system working
- Deep navigation functional
```

### Phase 3: Business Operations Integration

#### Test F3.1: Daily Sales Entry
```dart
// Test Case: Daily Sales Record Creation
1. Navigate to Daily Sales entry
2. Select date, shop, salesman
3. Add multiple product entries
4. Split payments across methods (cash/card/UPI/credit)
5. Submit record via /api/sales/daily-records
6. Verify success feedback and record status

// Expected Results:
- Form validation working
- Multi-payment calculation accurate
- Backend integration successful
- Status tracking functional
```

#### Test F3.2: Approval Workflows
```dart
// Test Case: Manager Approval Flow (Manager Role)
1. Login as manager
2. Navigate to pending approvals
3. View pending daily records
4. Review record details
5. Approve/reject with notes
6. Verify status update and notifications

// Expected Results:
- Pending items loaded correctly
- Approval actions successful
- Status updates in real-time
- Notification system working
```

### Phase 4: Financial Operations Integration

#### Test F4.1: Money Collection Flow (Critical)
```dart
// Test Case: 15-Minute Money Collection (Assistant Manager)
1. Login as assistant_manager
2. Navigate to money collection
3. Enter collection details
4. Submit collection via /api/finance/assistant-manager/money-collections
5. Verify 15-minute countdown timer
6. Test manager approval within deadline
7. Confirm collection status updates

// Expected Results:
- Collection submitted successfully
- Countdown timer accurate
- Approval process working
- Status tracking functional
- Deadline enforcement working
```

---

## 🔍 Critical Issues & Gap Analysis

### Backend Issues Identified

#### 1. **Gateway Routing Problems**
- **Issue**: Some gateway proxy routes not properly configured
- **Impact**: Direct service access needed for reliability
- **Solution**: Use direct service URLs in Flutter app
```dart
class ApiConfig {
  static const String authBaseUrl = 'http://localhost:8091';
  static const String salesBaseUrl = 'http://localhost:8092';
  // Direct service access instead of gateway
}
```

#### 2. **Missing OTP Delivery System**
- **Issue**: OTP sending via SMS/Email not implemented
- **Impact**: Development uses default OTP "000000"
- **Solution**: Implement proper OTP delivery for production

#### 3. **Session Management**
- **Issue**: Redis session management working correctly
- **Status**: ✅ Validated and functional
- **Implementation**: JWT + Redis session validation

### Frontend Integration Gaps

#### 1. **Dashboard Service Configuration**
```dart
// Issue: Dashboard service not properly configured in main.dart
// Solution: Ensure DashboardService is properly injected
ChangeNotifierProxyProvider3<AuthService, InventoryService, SalesService, DashboardService>(
  create: (context) => DashboardService(
    authService: context.read<AuthService>(),
    inventoryService: context.read<InventoryService>(),
    salesService: context.read<SalesService>(),
  ),
  update: (context, auth, inventory, sales, dashboard) =>
    dashboard ?? DashboardService(
      authService: auth,
      inventoryService: inventory,
      salesService: sales,
    ),
)
```

#### 2. **Error Handling & Offline Support**
```dart
// Required: Comprehensive error handling
class HttpService {
  Future<ApiResponse> handleRequest() async {
    try {
      // Network request
    } catch (e) {
      if (e is SocketException) {
        return ApiResponse.error('Network connection failed');
      }
      if (e is TimeoutException) {
        return ApiResponse.error('Request timeout');
      }
      return ApiResponse.error('Unknown error occurred');
    }
  }
}
```

#### 3. **Real-Time Updates**
```dart
// Required: Polling or WebSocket integration
class PendingApprovalsService {
  Timer? _pollingTimer;
  
  void startPolling() {
    _pollingTimer = Timer.periodic(Duration(seconds: 30), (_) {
      fetchPendingApprovals();
    });
  }
}
```

---

## 🎯 Industrial-Grade Implementation Plan

### Phase 1: Core Fixes (Priority 1)
1. **Fix Flutter Syntax Errors**: Resolve home_screen.dart compilation issues
2. **Complete Dashboard Integration**: Ensure DashboardService properly connected
3. **Test Authentication Flow**: Verify OTP login end-to-end
4. **Backend API Validation**: Test all critical endpoints

### Phase 2: Business Logic Validation (Priority 2)
1. **15-Minute Money Collection**: Test time-critical approval workflow
2. **Multi-Payment Sales**: Validate payment split calculations
3. **Approval Workflows**: Test manager/admin approval chains
4. **Role-Based Permissions**: Validate access control enforcement

### Phase 3: Production Readiness (Priority 3)
1. **Error Handling**: Implement comprehensive error boundaries
2. **Offline Support**: Add local data caching
3. **Performance Optimization**: Implement lazy loading and caching
4. **Security Hardening**: Add API rate limiting and validation

---

## ✅ Success Criteria

### Backend Validation
- [ ] All 5 microservices healthy and responding
- [ ] Authentication and authorization working 100%
- [ ] Multi-tenant data isolation verified
- [ ] All business workflows functional
- [ ] Role-based access control enforced
- [ ] Critical 15-minute money collection working

### Frontend Validation  
- [ ] App builds and runs without errors
- [ ] Authentication flow complete and functional
- [ ] Dashboard displays real backend data
- [ ] All navigation and quick actions working
- [ ] Role-based UI elements properly displayed
- [ ] Error handling and offline states implemented

### Integration Validation
- [ ] 100% API endpoint coverage
- [ ] Real-time data synchronization
- [ ] Business logic validation complete
- [ ] Performance meets industry standards
- [ ] Security implementation validated
- [ ] User experience matches modern app standards

---

## 📊 Final Testing Checklist

### Pre-Production Validation
- [ ] Load testing with concurrent users
- [ ] Database performance under load
- [ ] Redis caching efficiency validation
- [ ] JWT token expiry and refresh handling
- [ ] Multi-tenant security validation
- [ ] Mobile app performance on devices

### Business Process Validation
- [ ] Complete sales cycle testing
- [ ] Approval workflow testing
- [ ] Financial collection process validation
- [ ] Inventory management workflow
- [ ] Reporting accuracy validation
- [ ] User role transition testing

This comprehensive testing script ensures 100% backend-frontend integration with industrial-grade reliability and performance standards.
# LiquorPro Flutter API Integration Guide

## 🚀 Quick Start for Flutter Development

This comprehensive guide provides all API endpoints with cURL examples converted to Flutter HTTP requests for seamless integration with hot reload support.

### 📋 Table of Contents
1. [Environment Setup](#environment-setup)
2. [Authentication APIs](#authentication-apis)
3. [Admin & User Management APIs](#admin--user-management-apis)
4. [Sales Workflow APIs](#sales-workflow-apis)
5. [Inventory Management APIs](#inventory-management-apis)
6. [Finance APIs](#finance-apis)
7. [SaaS & Subscription APIs](#saas--subscription-apis)
8. [Flutter Integration Examples](#flutter-integration-examples)
9. [Hot Reload Development Tips](#hot-reload-development-tips)

---

## 🔧 Environment Setup

### Backend Services URLs
```dart
class ApiConfig {
  static const String baseUrl = 'http://localhost:8090'; // Gateway URL
  static const String authService = 'http://localhost:8091';
  static const String salesService = 'http://localhost:8092';
  static const String inventoryService = 'http://localhost:8093';
  static const String financeService = 'http://localhost:8094';
  
  // For production
  static const String prodBaseUrl = 'https://your-domain.com';
}
```

### Flutter HTTP Client Setup
```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiClient {
  static String? _authToken;
  static String? _refreshToken;
  
  static void setAuthToken(String token) {
    _authToken = token;
  }
  
  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };
  
  static Future<http.Response> get(String endpoint) async {
    return await http.get(
      Uri.parse('${ApiConfig.baseUrl}$endpoint'),
      headers: headers,
    );
  }
  
  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    return await http.post(
      Uri.parse('${ApiConfig.baseUrl}$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }
  
  static Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    return await http.put(
      Uri.parse('${ApiConfig.baseUrl}$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }
  
  static Future<http.Response> delete(String endpoint) async {
    return await http.delete(
      Uri.parse('${ApiConfig.baseUrl}$endpoint'),
      headers: headers,
    );
  }
}
```

---

## 🔐 Authentication APIs

### 1. User Registration with Tenant Creation

**cURL:**
```bash
curl -X POST http://localhost:8090/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "email": "admin@liquorstore.com",
    "password": "SecurePass123!",
    "first_name": "Admin",
    "last_name": "User",
    "phone": "+1234567890",
    "tenant_name": "My Liquor Store",
    "company_name": "My Liquor Store LLC"
  }'
```

**Flutter:**
```dart
class AuthService {
  static Future<Map<String, dynamic>?> register({
    required String username,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    required String tenantName,
    required String companyName,
  }) async {
    try {
      final response = await ApiClient.post('/api/auth/register', {
        'username': username,
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'tenant_name': tenantName,
        'company_name': companyName,
      });
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        ApiClient.setAuthToken(data['token']);
        return data;
      }
      return null;
    } catch (e) {
      print('Registration error: $e');
      return null;
    }
  }
}
```

### 2. User Login

**cURL:**
```bash
curl -X POST http://localhost:8090/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "SecurePass123!"
  }'
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> login({
  required String username,
  required String password,
}) async {
  try {
    final response = await ApiClient.post('/api/auth/login', {
      'username': username,
      'password': password,
    });
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      ApiClient.setAuthToken(data['token']);
      return data;
    }
    return null;
  } catch (e) {
    print('Login error: $e');
    return null;
  }
}
```

### 3. Get User Profile

**cURL:**
```bash
curl -X GET http://localhost:8090/api/auth/profile \
  -H "Authorization: Bearer {TOKEN}"
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> getProfile() async {
  try {
    final response = await ApiClient.get('/api/auth/profile');
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    print('Get profile error: $e');
    return null;
  }
}
```

### 4. Update User Profile

**cURL:**
```bash
curl -X PUT http://localhost:8090/api/auth/profile \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "Updated",
    "last_name": "Name",
    "phone": "+1234567890"
  }'
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> updateProfile({
  required String firstName,
  required String lastName,
  required String phone,
}) async {
  try {
    final response = await ApiClient.put('/api/auth/profile', {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
    });
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    print('Update profile error: $e');
    return null;
  }
}
```

### 5. Change Password

**cURL:**
```bash
curl -X PUT http://localhost:8090/api/auth/change-password \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "current_password": "oldpass",
    "new_password": "newpass"
  }'
```

**Flutter:**
```dart
static Future<bool> changePassword({
  required String currentPassword,
  required String newPassword,
}) async {
  try {
    final response = await ApiClient.put('/api/auth/change-password', {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    
    return response.statusCode == 200;
  } catch (e) {
    print('Change password error: $e');
    return false;
  }
}
```

### 6. Logout

**cURL:**
```bash
curl -X POST http://localhost:8090/api/auth/logout \
  -H "Authorization: Bearer {TOKEN}"
```

**Flutter:**
```dart
static Future<bool> logout() async {
  try {
    final response = await ApiClient.post('/api/auth/logout', {});
    
    if (response.statusCode == 200) {
      ApiClient.setAuthToken(null);
      return true;
    }
    return false;
  } catch (e) {
    print('Logout error: $e');
    return false;
  }
}
```

---

## 👥 Admin & User Management APIs

### 1. Create Shop

**cURL:**
```bash
curl -X POST http://localhost:8090/api/admin/shops \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Main Store",
    "address": "123 Main Street",
    "phone": "+1234567890",
    "license_number": "LIC-001"
  }'
```

**Flutter:**
```dart
class AdminService {
  static Future<Map<String, dynamic>?> createShop({
    required String name,
    required String address,
    required String phone,
    required String licenseNumber,
  }) async {
    try {
      final response = await ApiClient.post('/api/admin/shops', {
        'name': name,
        'address': address,
        'phone': phone,
        'license_number': licenseNumber,
      });
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Create shop error: $e');
      return null;
    }
  }
}
```

### 2. Get All Shops

**cURL:**
```bash
curl -X GET http://localhost:8090/api/admin/shops \
  -H "Authorization: Bearer {TOKEN}"
```

**Flutter:**
```dart
static Future<List<Map<String, dynamic>>?> getShops() async {
  try {
    final response = await ApiClient.get('/api/admin/shops');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['shops'] ?? []);
    }
    return null;
  } catch (e) {
    print('Get shops error: $e');
    return null;
  }
}
```

### 3. Create User

**cURL:**
```bash
curl -X POST http://localhost:8090/api/admin/users \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "manager1",
    "email": "manager@store.com",
    "password": "SecurePass123!",
    "first_name": "Manager",
    "last_name": "User",
    "phone": "+1234567891",
    "role": "manager"
  }'
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> createUser({
  required String username,
  required String email,
  required String password,
  required String firstName,
  required String lastName,
  required String phone,
  required String role,
}) async {
  try {
    final response = await ApiClient.post('/api/admin/users', {
      'username': username,
      'email': email,
      'password': password,
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'role': role,
    });
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    print('Create user error: $e');
    return null;
  }
}
```

### 4. Get All Users

**cURL:**
```bash
curl -X GET http://localhost:8090/api/admin/users \
  -H "Authorization: Bearer {TOKEN}"
```

**Flutter:**
```dart
static Future<List<Map<String, dynamic>>?> getUsers() async {
  try {
    final response = await ApiClient.get('/api/admin/users');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['users'] ?? []);
    }
    return null;
  } catch (e) {
    print('Get users error: $e');
    return null;
  }
}
```

### 5. Create Salesman

**cURL:**
```bash
curl -X POST http://localhost:8090/api/admin/salesmen \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "user-uuid",
    "shop_id": "shop-uuid",
    "employee_id": "EMP-001",
    "name": "Salesman Name",
    "phone": "+1234567892",
    "join_date": "2024-01-15"
  }'
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> createSalesman({
  required String userId,
  required String shopId,
  required String employeeId,
  required String name,
  required String phone,
  required String joinDate,
}) async {
  try {
    final response = await ApiClient.post('/api/admin/salesmen', {
      'user_id': userId,
      'shop_id': shopId,
      'employee_id': employeeId,
      'name': name,
      'phone': phone,
      'join_date': joinDate,
    });
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    print('Create salesman error: $e');
    return null;
  }
}
```

---

## 📦 Inventory Management APIs

### 1. Create Category

**cURL:**
```bash
curl -X POST http://localhost:8090/api/inventory/categories \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Whiskey",
    "description": "All types of whiskey products"
  }'
```

**Flutter:**
```dart
class InventoryService {
  static Future<Map<String, dynamic>?> createCategory({
    required String name,
    required String description,
  }) async {
    try {
      final response = await ApiClient.post('/api/inventory/categories', {
        'name': name,
        'description': description,
      });
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Create category error: $e');
      return null;
    }
  }
}
```

### 2. Get All Categories

**cURL:**
```bash
curl -X GET http://localhost:8090/api/inventory/categories \
  -H "Authorization: Bearer {TOKEN}"
```

**Flutter:**
```dart
static Future<List<Map<String, dynamic>>?> getCategories() async {
  try {
    final response = await ApiClient.get('/api/inventory/categories');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['categories'] ?? []);
    }
    return null;
  } catch (e) {
    print('Get categories error: $e');
    return null;
  }
}
```

### 3. Create Brand

**cURL:**
```bash
curl -X POST http://localhost:8090/api/inventory/brands \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Premium Spirits",
    "description": "Premium quality spirits brand"
  }'
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> createBrand({
  required String name,
  required String description,
}) async {
  try {
    final response = await ApiClient.post('/api/inventory/brands', {
      'name': name,
      'description': description,
    });
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    print('Create brand error: $e');
    return null;
  }
}
```

### 4. Create Product

**cURL:**
```bash
curl -X POST http://localhost:8090/api/inventory/products \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Premium Whiskey 750ml",
    "category_id": "category-uuid",
    "brand_id": "brand-uuid",
    "size": "750ml",
    "alcohol_content": 40.0,
    "description": "Premium aged whiskey",
    "barcode": "1234567890123",
    "sku": "WHIS-750-PREM",
    "cost_price": 800.00,
    "selling_price": 1200.00,
    "mrp": 1500.00
  }'
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> createProduct({
  required String name,
  required String categoryId,
  required String brandId,
  required String size,
  required double alcoholContent,
  required String description,
  required String barcode,
  required String sku,
  required double costPrice,
  required double sellingPrice,
  required double mrp,
}) async {
  try {
    final response = await ApiClient.post('/api/inventory/products', {
      'name': name,
      'category_id': categoryId,
      'brand_id': brandId,
      'size': size,
      'alcohol_content': alcoholContent,
      'description': description,
      'barcode': barcode,
      'sku': sku,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      'mrp': mrp,
    });
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    print('Create product error: $e');
    return null;
  }
}
```

### 5. Get Products with Search

**cURL:**
```bash
curl -X GET "http://localhost:8090/api/inventory/products?search=whiskey&limit=20&offset=0" \
  -H "Authorization: Bearer {TOKEN}"
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> getProducts({
  String? search,
  int limit = 20,
  int offset = 0,
}) async {
  try {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
    };
    
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/inventory/products')
        .replace(queryParameters: queryParams);
    
    final response = await http.get(uri, headers: ApiClient.headers);
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    print('Get products error: $e');
    return null;
  }
}
```

### 6. Adjust Stock

**cURL:**
```bash
curl -X POST http://localhost:8090/api/inventory/stock/adjust \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "shop_id": "shop-uuid",
    "product_id": "product-uuid",
    "adjustment_type": "increase",
    "quantity": 100,
    "reason": "Initial stock",
    "cost_price": 800.00,
    "notes": "Opening stock"
  }'
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> adjustStock({
  required String shopId,
  required String productId,
  required String adjustmentType, // "increase" or "decrease"
  required int quantity,
  required String reason,
  required double costPrice,
  String? notes,
}) async {
  try {
    final response = await ApiClient.post('/api/inventory/stock/adjust', {
      'shop_id': shopId,
      'product_id': productId,
      'adjustment_type': adjustmentType,
      'quantity': quantity,
      'reason': reason,
      'cost_price': costPrice,
      if (notes != null) 'notes': notes,
    });
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    print('Adjust stock error: $e');
    return null;
  }
}
```

---

## 🛍️ Sales Workflow APIs

### 1. Create Daily Sales Record (Bulk Entry)

**cURL:**
```bash
curl -X POST http://localhost:8090/api/sales/daily-records \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "record_date": "2024-01-15",
    "shop_id": "shop-uuid",
    "salesman_id": "salesman-uuid",
    "total_sales_amount": 25000.00,
    "total_cash_amount": 15000.00,
    "total_card_amount": 7000.00,
    "total_upi_amount": 3000.00,
    "notes": "Daily sales record",
    "items": [
      {
        "product_id": "product-uuid",
        "quantity": 20,
        "unit_price": 1200.00,
        "total_amount": 24000.00,
        "cash_amount": 14000.00,
        "card_amount": 7000.00,
        "upi_amount": 3000.00
      }
    ]
  }'
```

**Flutter:**
```dart
class SalesService {
  static Future<Map<String, dynamic>?> createDailySalesRecord({
    required String recordDate,
    required String shopId,
    required String salesmanId,
    required double totalSalesAmount,
    required double totalCashAmount,
    required double totalCardAmount,
    required double totalUpiAmount,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final response = await ApiClient.post('/api/sales/daily-records', {
        'record_date': recordDate,
        'shop_id': shopId,
        'salesman_id': salesmanId,
        'total_sales_amount': totalSalesAmount,
        'total_cash_amount': totalCashAmount,
        'total_card_amount': totalCardAmount,
        'total_upi_amount': totalUpiAmount,
        if (notes != null) 'notes': notes,
        'items': items,
      });
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Create daily sales record error: $e');
      return null;
    }
  }
}
```

### 2. Get Daily Sales Records

**cURL:**
```bash
curl -X GET "http://localhost:8090/api/sales/daily-records?date=2024-01-15&status=pending" \
  -H "Authorization: Bearer {TOKEN}"
```

**Flutter:**
```dart
static Future<List<Map<String, dynamic>>?> getDailySalesRecords({
  String? date,
  String? status,
  int limit = 20,
  int offset = 0,
}) async {
  try {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (date != null) 'date': date,
      if (status != null) 'status': status,
    };
    
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/sales/daily-records')
        .replace(queryParameters: queryParams);
    
    final response = await http.get(uri, headers: ApiClient.headers);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['records'] ?? []);
    }
    return null;
  } catch (e) {
    print('Get daily sales records error: $e');
    return null;
  }
}
```

### 3. Approve Daily Sales Record

**cURL:**
```bash
curl -X POST http://localhost:8090/api/sales/daily-records/{id}/approve \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "notes": "Approved after verification"
  }'
```

**Flutter:**
```dart
static Future<bool> approveDailySalesRecord({
  required String recordId,
  String? notes,
}) async {
  try {
    final response = await ApiClient.post('/api/sales/daily-records/$recordId/approve', {
      if (notes != null) 'notes': notes,
    });
    
    return response.statusCode == 200;
  } catch (e) {
    print('Approve daily sales record error: $e');
    return false;
  }
}
```

### 4. Create Individual Sale

**cURL:**
```bash
curl -X POST http://localhost:8090/api/sales/sales \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "shop_id": "shop-uuid",
    "salesman_id": "salesman-uuid",
    "sale_date": "2024-01-15T14:30:00Z",
    "customer_name": "Customer Name",
    "customer_phone": "+1234567999",
    "payment_method": "cash",
    "items": [
      {
        "product_id": "product-uuid",
        "quantity": 1,
        "unit_price": 1200.00,
        "total_price": 1200.00
      }
    ],
    "total_amount": 1200.00,
    "paid_amount": 1200.00,
    "payment_status": "paid"
  }'
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> createSale({
  required String shopId,
  required String salesmanId,
  required String saleDate,
  String? customerName,
  String? customerPhone,
  required String paymentMethod,
  required List<Map<String, dynamic>> items,
  required double totalAmount,
  required double paidAmount,
  required String paymentStatus,
}) async {
  try {
    final response = await ApiClient.post('/api/sales/sales', {
      'shop_id': shopId,
      'salesman_id': salesmanId,
      'sale_date': saleDate,
      if (customerName != null) 'customer_name': customerName,
      if (customerPhone != null) 'customer_phone': customerPhone,
      'payment_method': paymentMethod,
      'items': items,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'payment_status': paymentStatus,
    });
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    print('Create sale error: $e');
    return null;
  }
}
```

### 5. Get Sales List

**cURL:**
```bash
curl -X GET "http://localhost:8090/api/sales/sales?date=2024-01-15&status=pending" \
  -H "Authorization: Bearer {TOKEN}"
```

**Flutter:**
```dart
static Future<List<Map<String, dynamic>>?> getSales({
  String? date,
  String? status,
  String? shopId,
  int limit = 20,
  int offset = 0,
}) async {
  try {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (date != null) 'date': date,
      if (status != null) 'status': status,
      if (shopId != null) 'shop_id': shopId,
    };
    
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/sales/sales')
        .replace(queryParameters: queryParams);
    
    final response = await http.get(uri, headers: ApiClient.headers);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['sales'] ?? []);
    }
    return null;
  } catch (e) {
    print('Get sales error: $e');
    return null;
  }
}
```

### 6. Get Pending Sales (Manager View)

**cURL:**
```bash
curl -X GET http://localhost:8090/api/sales/pending \
  -H "Authorization: Bearer {TOKEN}"
```

**Flutter:**
```dart
static Future<List<Map<String, dynamic>>?> getPendingSales() async {
  try {
    final response = await ApiClient.get('/api/sales/pending');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['pending_sales'] ?? []);
    }
    return null;
  } catch (e) {
    print('Get pending sales error: $e');
    return null;
  }
}
```

---

## 💰 Finance APIs

### 1. Create Money Collection (CRITICAL 15-minute deadline)

**cURL:**
```bash
curl -X POST http://localhost:8090/api/finance/money-collection \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "executive_id": "manager-uuid",
    "shop_id": "shop-uuid",
    "amount": 25000.00,
    "collection_type": "daily_sales",
    "description": "Daily sales collection",
    "notes": "Critical 15-minute approval deadline"
  }'
```

**Flutter:**
```dart
class FinanceService {
  static Future<Map<String, dynamic>?> createMoneyCollection({
    required String executiveId,
    required String shopId,
    required double amount,
    required String collectionType,
    required String description,
    String? notes,
  }) async {
    try {
      final response = await ApiClient.post('/api/finance/money-collection', {
        'executive_id': executiveId,
        'shop_id': shopId,
        'amount': amount,
        'collection_type': collectionType,
        'description': description,
        if (notes != null) 'notes': notes,
      });
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Create money collection error: $e');
      return null;
    }
  }
}
```

### 2. Get Money Collections with Status

**cURL:**
```bash
curl -X GET "http://localhost:8090/api/finance/money-collection?status=pending" \
  -H "Authorization: Bearer {TOKEN}"
```

**Flutter:**
```dart
static Future<List<Map<String, dynamic>>?> getMoneyCollections({
  String? status,
  int limit = 20,
  int offset = 0,
}) async {
  try {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (status != null) 'status': status,
    };
    
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/finance/money-collection')
        .replace(queryParameters: queryParams);
    
    final response = await http.get(uri, headers: ApiClient.headers);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['collections'] ?? []);
    }
    return null;
  } catch (e) {
    print('Get money collections error: $e');
    return null;
  }
}
```

### 3. Approve Money Collection (URGENT - Must be within 15 minutes)

**cURL:**
```bash
curl -X POST http://localhost:8090/api/finance/money-collection/{id}/approve \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "notes": "Approved - amount verified"
  }'
```

**Flutter:**
```dart
static Future<bool> approveMoneyCollection({
  required String collectionId,
  String? notes,
}) async {
  try {
    final response = await ApiClient.post('/api/finance/money-collection/$collectionId/approve', {
      if (notes != null) 'notes': notes,
    });
    
    return response.statusCode == 200;
  } catch (e) {
    print('Approve money collection error: $e');
    return false;
  }
}
```

### 4. Create Expense

**cURL:**
```bash
curl -X POST http://localhost:8090/api/finance/expenses \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "shop_id": "shop-uuid",
    "expense_date": "2024-01-15",
    "description": "Office supplies",
    "amount": 5000.00,
    "payment_method": "cash",
    "receipt_no": "RCP-001",
    "vendor_name": "Office Supplies Co",
    "notes": "Monthly office supplies"
  }'
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> createExpense({
  required String shopId,
  required String expenseDate,
  required String description,
  required double amount,
  required String paymentMethod,
  String? receiptNo,
  String? vendorName,
  String? notes,
}) async {
  try {
    final response = await ApiClient.post('/api/finance/expenses', {
      'shop_id': shopId,
      'expense_date': expenseDate,
      'description': description,
      'amount': amount,
      'payment_method': paymentMethod,
      if (receiptNo != null) 'receipt_no': receiptNo,
      if (vendorName != null) 'vendor_name': vendorName,
      if (notes != null) 'notes': notes,
    });
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    print('Create expense error: $e');
    return null;
  }
}
```

### 5. Create Vendor

**cURL:**
```bash
curl -X POST http://localhost:8090/api/finance/vendors \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Liquor Supplier",
    "contact_person": "John Supplier",
    "phone": "+1234567800",
    "email": "supplier@liquor.com",
    "address": "456 Supplier Street",
    "city": "Supply City",
    "state": "State",
    "gst_number": "22AAAAA0000A1Z5",
    "payment_terms": "Net 30",
    "credit_limit": 500000.00
  }'
```

**Flutter:**
```dart
static Future<Map<String, dynamic>?> createVendor({
  required String name,
  required String contactPerson,
  required String phone,
  required String email,
  required String address,
  required String city,
  required String state,
  String? gstNumber,
  String? paymentTerms,
  double? creditLimit,
}) async {
  try {
    final response = await ApiClient.post('/api/finance/vendors', {
      'name': name,
      'contact_person': contactPerson,
      'phone': phone,
      'email': email,
      'address': address,
      'city': city,
      'state': state,
      if (gstNumber != null) 'gst_number': gstNumber,
      if (paymentTerms != null) 'payment_terms': paymentTerms,
      if (creditLimit != null) 'credit_limit': creditLimit,
    });
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    print('Create vendor error: $e');
    return null;
  }
}
```

---

## 🌐 Gateway & Health Check APIs

### 1. Service Discovery

**cURL:**
```bash
curl -X GET http://localhost:8090/gateway/services
```

**Flutter:**
```dart
class GatewayService {
  static Future<Map<String, dynamic>?> getServicesStatus() async {
    try {
      final response = await ApiClient.get('/gateway/services');
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Get services status error: $e');
      return null;
    }
  }
}
```

### 2. Gateway Health Check

**cURL:**
```bash
curl -X GET http://localhost:8090/gateway/health
```

**Flutter:**
```dart
static Future<bool> checkGatewayHealth() async {
  try {
    final response = await ApiClient.get('/gateway/health');
    return response.statusCode == 200;
  } catch (e) {
    print('Gateway health check error: $e');
    return false;
  }
}
```

---

## 🎯 Flutter Integration Examples

### Complete Flutter App Structure

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
      child: MaterialApp(
        title: 'LiquorPro',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        if (authService.isAuthenticated) {
          return DashboardScreen();
        } else {
          return LoginScreen();
        }
      },
    );
  }
}
```

### Auth Service Provider

```dart
// lib/services/auth_service.dart
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class AuthService extends ChangeNotifier {
  bool _isAuthenticated = false;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _tenant;
  
  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get tenant => _tenant;
  
  Future<bool> login(String username, String password) async {
    try {
      final response = await ApiClient.post('/api/auth/login', {
        'username': username,
        'password': password,
      });
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        ApiClient.setAuthToken(data['token']);
        _user = data['user'];
        _tenant = data['tenant'];
        _isAuthenticated = true;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }
  
  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    required String tenantName,
    required String companyName,
  }) async {
    try {
      final response = await ApiClient.post('/api/auth/register', {
        'username': username,
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'tenant_name': tenantName,
        'company_name': companyName,
      });
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        ApiClient.setAuthToken(data['token']);
        _user = data['user'];
        _tenant = data['tenant'];
        _isAuthenticated = true;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print('Registration error: $e');
      return false;
    }
  }
  
  Future<void> logout() async {
    try {
      await ApiClient.post('/api/auth/logout', {});
    } catch (e) {
      print('Logout error: $e');
    } finally {
      ApiClient.setAuthToken(null);
      _user = null;
      _tenant = null;
      _isAuthenticated = false;
      notifyListeners();
    }
  }
}
```

### Login Screen with Hot Reload

```dart
// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  
  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
    });
    
    final authService = Provider.of<AuthService>(context, listen: false);
    final success = await authService.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );
    
    setState(() {
      _isLoading = false;
    });
    
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login failed. Please check your credentials.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('LiquorPro Login'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Welcome to LiquorPro',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your username';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  return null;
                },
              ),
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text('Login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Dashboard Screen with Navigation

```dart
// lib/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'sales/sales_screen.dart';
import 'inventory/inventory_screen.dart';
import 'finance/finance_screen.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  
  final List<Widget> _screens = [
    DashboardHomeScreen(),
    SalesScreen(),
    InventoryScreen(),
    FinanceScreen(),
  ];
  
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('LiquorPro Dashboard'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton(
            icon: Icon(Icons.account_circle),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: Text('Profile'),
                onTap: () {
                  // Navigate to profile screen
                },
              ),
              PopupMenuItem(
                child: Text('Logout'),
                onTap: () async {
                  await authService.logout();
                },
              ),
            ],
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: 'Sales',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory),
            label: 'Inventory',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance),
            label: 'Finance',
          ),
        ],
      ),
    );
  }
}

class DashboardHomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome, ${authService.user?['first_name'] ?? 'User'}!',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: 8),
          Text(
            'Tenant: ${authService.tenant?['name'] ?? 'Unknown'}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          SizedBox(height: 24),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                _buildDashboardCard(
                  context,
                  'Sales',
                  Icons.shopping_cart,
                  Colors.green,
                  () {
                    // Navigate to sales
                  },
                ),
                _buildDashboardCard(
                  context,
                  'Inventory',
                  Icons.inventory,
                  Colors.blue,
                  () {
                    // Navigate to inventory
                  },
                ),
                _buildDashboardCard(
                  context,
                  'Finance',
                  Icons.account_balance,
                  Colors.orange,
                  () {
                    // Navigate to finance
                  },
                ),
                _buildDashboardCard(
                  context,
                  'Reports',
                  Icons.analytics,
                  Colors.purple,
                  () {
                    // Navigate to reports
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDashboardCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: color,
              ),
              SizedBox(height: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 🔥 Hot Reload Development Tips

### 1. Environment Configuration for Hot Reload

```dart
// lib/config/environment.dart
class Environment {
  static const bool isDevelopment = true;
  static const String baseUrl = isDevelopment 
      ? 'http://localhost:8090'
      : 'https://your-production-domain.com';
  
  // For Android emulator use: http://10.0.2.2:8090
  // For iOS simulator use: http://localhost:8090
  // For physical device use: http://192.168.1.xxx:8090 (your computer's IP)
}
```

### 2. API Client with Hot Reload Support

```dart
// lib/services/api_client.dart
class ApiClient {
  static const Duration timeout = Duration(seconds: 10);
  
  static Future<http.Response> _makeRequest(
    Future<http.Response> Function() requestFn,
  ) async {
    try {
      final response = await requestFn().timeout(timeout);
      
      // Log for development
      if (Environment.isDevelopment) {
        print('API Response: ${response.statusCode} - ${response.body}');
      }
      
      return response;
    } catch (e) {
      if (Environment.isDevelopment) {
        print('API Error: $e');
      }
      rethrow;
    }
  }
  
  static Future<http.Response> get(String endpoint) async {
    return _makeRequest(() => http.get(
      Uri.parse('${Environment.baseUrl}$endpoint'),
      headers: headers,
    ));
  }
  
  // ... other methods
}
```

### 3. State Management for Hot Reload

```dart
// lib/services/app_state.dart
import 'package:flutter/foundation.dart';

class AppState extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  void setError(String? error) {
    _error = error;
    notifyListeners();
  }
  
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
```

### 4. Development Helpers

```dart
// lib/utils/dev_helpers.dart
class DevHelpers {
  static void logApiCall(String method, String endpoint, dynamic body) {
    if (Environment.isDevelopment) {
      print('🌐 API $method $endpoint');
      if (body != null) {
        print('📤 Body: $body');
      }
    }
  }
  
  static void logApiResponse(int statusCode, dynamic response) {
    if (Environment.isDevelopment) {
      print('📥 Response $statusCode: $response');
    }
  }
  
  static void logError(String operation, dynamic error) {
    if (Environment.isDevelopment) {
      print('❌ Error in $operation: $error');
    }
  }
}
```

### 5. pubspec.yaml Dependencies

```yaml
name: liquorpro_flutter
description: LiquorPro Flutter Application

version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  
  # State Management
  provider: ^6.1.1
  
  # HTTP Requests
  http: ^1.1.0
  
  # Local Storage
  shared_preferences: ^2.2.2
  
  # JSON Serialization
  json_annotation: ^4.8.1
  
  # UI Components
  cupertino_icons: ^1.0.6
  
  # Date/Time Utilities
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  
  # Code Generation
  build_runner: ^2.4.7
  json_serializable: ^6.7.1
  
  # Linting
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
```

### 6. Quick Start Commands

```bash
# Create new Flutter project
flutter create liquorpro_flutter
cd liquorpro_flutter

# Add dependencies
flutter pub add provider http shared_preferences json_annotation intl
flutter pub add --dev build_runner json_serializable flutter_lints

# Run with hot reload
flutter run

# Run on specific device
flutter run -d chrome
flutter run -d android
flutter run -d ios
```

---

## 🎯 Complete Development Workflow

### 1. Start Backend Services
```bash
cd /path/to/Go-Backend-Liquor
make dev
```

### 2. Start Flutter Development
```bash
cd /path/to/liquorpro_flutter
flutter run
```

### 3. Test API Integration
- Use the cURL examples to test backend APIs
- Convert working cURL commands to Flutter HTTP requests
- Use hot reload to instantly see changes

### 4. Development Best Practices
- Keep backend services running during Flutter development
- Use environment variables for API URLs
- Implement proper error handling for API calls
- Use state management (Provider) for authentication state
- Test on both emulator and physical device

This comprehensive guide provides everything needed to build a Flutter application that integrates seamlessly with the LiquorPro backend APIs, with full support for hot reload development!
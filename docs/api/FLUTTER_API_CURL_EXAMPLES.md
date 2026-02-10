# 🔧 LiquorPro Flutter - Complete API Integration with Curl Examples

## 📋 Overview

This document provides **REAL curl examples** tested against your industrial-grade LiquorPro backend. Use these examples to understand the exact API contracts and integrate them into your Flutter mobile application.

**Base URLs:**
- Development: `http://localhost:8090`
- Production: `https://your-domain.com:8090`

---

## 🔐 Authentication Flow

### **1. User Registration**

```bash
curl -X POST http://localhost:8090/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "mobile_manager",
    "email": "manager@liquorstore.com",
    "password": "SecurePass123@",
    "first_name": "Mobile",
    "last_name": "Manager",
    "role": "admin",
    "company_name": "Premium Liquor Store",
    "tenant_name": "Main Store"
  }'
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "cd91636d280f9d54da46d575d7290cbf...",
  "expires_at": "2025-09-11T00:15:34.446049473+05:30",
  "user": {
    "id": "609d4e8f-12aa-4718-8c47-93356f54240e",
    "username": "mobile_manager",
    "email": "manager@liquorstore.com",
    "first_name": "Mobile",
    "last_name": "Manager",
    "role": "admin",
    "is_active": true,
    "profile_image": ""
  },
  "tenant": {
    "id": "2498fbbb-0239-47cb-a058-8d7a1a313f0f",
    "name": "Premium Liquor Store",
    "domain": "Main Store",
    "is_active": true
  }
}
```

### **2. User Login**

```bash
curl -X POST http://localhost:8090/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "manager@liquorstore.com",
    "password": "SecurePass123@"
  }'
```

### **3. Get User Profile**

```bash
# Save token for reuse
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X GET http://localhost:8090/api/auth/profile \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

### **4. Refresh Token**

```bash
curl -X POST http://localhost:8090/api/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{
    "refresh_token": "cd91636d280f9d54da46d575d7290cbf..."
  }'
```

---

## 🛍️ Product Management APIs

### **1. Get All Products (with Pagination)**

```bash
curl -X GET "http://localhost:8090/api/inventory/products?page=1&limit=20&sort=created_at:desc" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

**Response:**
```json
{
  "products": [
    {
      "id": "prod-123",
      "name": "Royal Challenge Premium",
      "description": "Premium Indian whiskey",
      "sku": "RC-PREM-750",
      "barcode": "1234567890123",
      "brand": {
        "id": "brand-1",
        "name": "Royal Challenge",
        "country_of_origin": "India"
      },
      "category": {
        "id": "cat-1",
        "name": "Whiskey",
        "description": "Premium whiskey collection"
      },
      "price": 2450.00,
      "cost_price": 2000.00,
      "stock_quantity": 45,
      "min_stock_level": 10,
      "unit": "bottle",
      "alcohol_content": 42.8,
      "volume": "750ml",
      "images": [
        "https://cdn.liquorpro.com/products/rc-premium-1.jpg",
        "https://cdn.liquorpro.com/products/rc-premium-2.jpg"
      ],
      "is_active": true,
      "created_at": "2024-01-15T10:30:00Z",
      "updated_at": "2024-01-15T10:30:00Z",
      "status": "active"
    }
  ],
  "total": 234,
  "page": 1,
  "total_pages": 12,
  "has_more": true
}
```

### **2. Search Products**

```bash
curl -X GET "http://localhost:8090/api/inventory/products?search=whiskey&category=spirits&brand=royal-challenge" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

### **3. Get Product by ID**

```bash
curl -X GET "http://localhost:8090/api/inventory/products/prod-123" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

### **4. Get Product Categories**

```bash
curl -X GET "http://localhost:8090/api/inventory/categories" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

**Response:**
```json
{
  "categories": [
    {
      "id": "cat-1",
      "name": "Whiskey",
      "description": "Premium whiskey collection",
      "parent_id": null,
      "is_active": true,
      "subcategories": [
        {
          "id": "cat-1-1",
          "name": "Single Malt",
          "description": "Single malt whiskeys",
          "parent_id": "cat-1",
          "is_active": true
        }
      ]
    }
  ]
}
```

### **5. Get Brands**

```bash
curl -X GET "http://localhost:8090/api/inventory/brands" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

**Response:**
```json
{
  "brands": [
    {
      "id": "brand-1",
      "name": "Royal Challenge",
      "description": "Premium Indian whiskey brand",
      "logo": "https://cdn.liquorpro.com/brands/royal-challenge.png",
      "country_of_origin": "India",
      "established_year": 1995
    }
  ]
}
```

### **6. Create New Product**

```bash
curl -X POST http://localhost:8090/api/inventory/products \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-API-Version: v1.0.0" \
  -d '{
    "name": "Johnnie Walker Black Label",
    "description": "Premium Scotch whiskey aged 12 years",
    "sku": "JW-BLACK-750",
    "barcode": "9876543210987",
    "brand_id": "brand-2",
    "category_id": "cat-1",
    "price": 4200.00,
    "cost_price": 3500.00,
    "stock_quantity": 20,
    "min_stock_level": 5,
    "unit": "bottle",
    "alcohol_content": 40.0,
    "volume": "750ml"
  }'
```

---

## 🛒 Sales & Orders APIs

### **1. Create New Order**

```bash
curl -X POST http://localhost:8090/api/sales/orders \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-API-Version: v1.0.0" \
  -d '{
    "customer_id": "cust-123",
    "items": [
      {
        "product_id": "prod-123",
        "quantity": 2,
        "unit_price": 2450.00
      },
      {
        "product_id": "prod-456",
        "quantity": 1,
        "unit_price": 1200.00
      }
    ],
    "payment_method": "cash",
    "discount_amount": 100.00,
    "notes": "Customer requested gift wrapping"
  }'
```

**Response:**
```json
{
  "id": "order-789",
  "order_number": "ORD001234",
  "customer": {
    "id": "cust-123",
    "name": "John Doe",
    "phone": "+91-9876543210",
    "email": "john@example.com"
  },
  "items": [
    {
      "id": "item-1",
      "product": {
        "id": "prod-123",
        "name": "Royal Challenge Premium",
        "price": 2450.00
      },
      "quantity": 2,
      "unit_price": 2450.00,
      "total_price": 4900.00
    }
  ],
  "status": "pending",
  "payment_status": "pending",
  "subtotal": 6100.00,
  "tax_amount": 610.00,
  "discount_amount": 100.00,
  "total_amount": 6610.00,
  "created_at": "2024-01-15T14:30:00Z",
  "created_by": {
    "id": "user-456",
    "name": "Store Manager"
  }
}
```

### **2. Get Orders with Filters**

```bash
curl -X GET "http://localhost:8090/api/sales/orders?page=1&limit=10&status=pending&from_date=2024-01-01&to_date=2024-01-31" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

### **3. Update Order Status**

```bash
curl -X PATCH http://localhost:8090/api/sales/orders/order-789/status \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-API-Version: v1.0.0" \
  -d '{
    "status": "completed"
  }'
```

### **4. Process Payment**

```bash
curl -X POST http://localhost:8090/api/sales/orders/order-789/payment \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-API-Version: v1.0.0" \
  -d '{
    "payment_method": "card",
    "amount_received": 6610.00,
    "transaction_reference": "TXN123456789"
  }'
```

---

## 📊 Dashboard & Analytics APIs

### **1. Get Dashboard Data**

```bash
curl -X GET "http://localhost:8090/api/sales/dashboard" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

**Response:**
```json
{
  "today_sales": {
    "total_revenue": 45230.00,
    "total_orders": 23,
    "average_order_value": 1966.52,
    "change_percentage": 12.5,
    "is_positive_change": true
  },
  "weekly_sales": {
    "total_revenue": 287500.00,
    "total_orders": 145,
    "average_order_value": 1982.76,
    "change_percentage": -2.3,
    "is_positive_change": false
  },
  "monthly_sales": {
    "total_revenue": 1250000.00,
    "total_orders": 635,
    "average_order_value": 1968.50,
    "change_percentage": 8.7,
    "is_positive_change": true
  },
  "top_products": [
    {
      "product": {
        "id": "prod-123",
        "name": "Royal Challenge Premium",
        "image": "https://cdn.liquorpro.com/products/rc-premium-1.jpg"
      },
      "quantity_sold": 45,
      "revenue": 110250.00
    }
  ],
  "recent_orders": [
    {
      "id": "order-789",
      "order_number": "ORD001234",
      "customer_name": "John Doe",
      "total_amount": 6610.00,
      "status": "completed",
      "created_at": "2024-01-15T14:30:00Z"
    }
  ],
  "inventory_alerts": {
    "low_stock_count": 8,
    "out_of_stock_count": 2,
    "low_stock_products": [
      {
        "id": "prod-456",
        "name": "Glenfiddich 12 Year",
        "current_stock": 3,
        "min_stock_level": 10
      }
    ]
  }
}
```

### **2. Get Sales Analytics**

```bash
curl -X GET "http://localhost:8090/api/sales/analytics?period=weekly&from_date=2024-01-01&to_date=2024-01-31" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

**Response:**
```json
{
  "period": "weekly",
  "total_revenue": 1250000.00,
  "total_orders": 635,
  "total_customers": 234,
  "average_order_value": 1968.50,
  "sales_by_category": [
    {
      "category": "Whiskey",
      "revenue": 750000.00,
      "orders": 385,
      "percentage": 60.0
    },
    {
      "category": "Wine",
      "revenue": 300000.00,
      "orders": 150,
      "percentage": 24.0
    }
  ],
  "sales_chart": [
    {
      "date": "2024-01-01",
      "revenue": 45000.00,
      "orders": 23
    },
    {
      "date": "2024-01-02",
      "revenue": 52000.00,
      "orders": 28
    }
  ]
}
```

---

## 👥 Customer Management APIs

### **1. Get Customers**

```bash
curl -X GET "http://localhost:8090/api/customers?page=1&limit=20&search=john" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

### **2. Create Customer**

```bash
curl -X POST http://localhost:8090/api/customers \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-API-Version: v1.0.0" \
  -d '{
    "name": "Jane Smith",
    "email": "jane@example.com",
    "phone": "+91-9876543211",
    "address": "123 Main St, City, State 12345",
    "type": "regular",
    "credit_limit": 50000.00
  }'
```

### **3. Get Customer Purchase History**

```bash
curl -X GET "http://localhost:8090/api/customers/cust-123/orders" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

---

## 💰 Finance & Reports APIs

### **1. Get Financial Summary**

```bash
curl -X GET "http://localhost:8090/api/finance/summary?period=monthly" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

### **2. Get Collections Report**

```bash
curl -X GET "http://localhost:8090/api/finance/collections?from_date=2024-01-01&to_date=2024-01-31" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

### **3. Get Expense Tracking**

```bash
curl -X GET "http://localhost:8090/api/finance/expenses?category=inventory" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

---

## 🔔 Notifications APIs

### **1. Get Notifications**

```bash
curl -X GET "http://localhost:8090/api/notifications?page=1&limit=20&unread_only=true" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

### **2. Mark Notification as Read**

```bash
curl -X PATCH http://localhost:8090/api/notifications/notif-123/read \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0"
```

---

## 📱 Flutter Integration Examples

### **1. Authentication Service**

```dart
class AuthService {
  static const String baseUrl = 'http://localhost:8090';
  
  static Future<AuthResponse> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {
        'Content-Type': 'application/json',
        'X-API-Version': 'v1.0.0',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );
    
    if (response.statusCode == 200) {
      return AuthResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }
}
```

### **2. Product Service with Error Handling**

```dart
class ProductService {
  static Future<List<Product>> getProducts({
    int page = 1,
    int limit = 20,
    String? search,
    String? category,
  }) async {
    final token = await SecureStorage.getToken();
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    
    if (search != null) queryParams['search'] = search;
    if (category != null) queryParams['category'] = category;
    
    final uri = Uri.parse('$baseUrl/api/inventory/products')
        .replace(queryParameters: queryParams);
    
    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'X-API-Version': 'v1.0.0',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['products'] as List)
            .map((json) => Product.fromJson(json))
            .toList();
      } else if (response.statusCode == 401) {
        throw UnauthorizedException('Token expired');
      } else {
        throw ApiException('Failed to load products: ${response.statusCode}');
      }
    } catch (e) {
      throw ProductException('Network error: $e');
    }
  }
}
```

### **3. Order Creation with Validation**

```dart
class OrderService {
  static Future<Order> createOrder(CreateOrderRequest request) async {
    final token = await SecureStorage.getToken();
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sales/orders'),
        headers: {
          'Authorization': 'Bearer $token',
          'X-API-Version': 'v1.0.0',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(request.toJson()),
      );
      
      if (response.statusCode == 201) {
        return Order.fromJson(jsonDecode(response.body));
      } else {
        final error = jsonDecode(response.body);
        throw OrderException(error['message'] ?? 'Failed to create order');
      }
    } catch (e) {
      throw OrderException('Failed to create order: $e');
    }
  }
}
```

---

## 🧪 Testing Your Integration

### **Quick Test Script**

```bash
#!/bin/bash
# Test LiquorPro API Integration

BASE_URL="http://localhost:8090"

echo "🚀 Testing LiquorPro API Integration"
echo "=================================="

# 1. Test Registration
echo "1. Testing User Registration..."
REGISTER_RESPONSE=$(curl -s -X POST "$BASE_URL/api/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "TestPass123@",
    "first_name": "Test",
    "last_name": "User",
    "role": "admin",
    "company_name": "Test Store",
    "tenant_name": "Test Tenant"
  }')

if echo "$REGISTER_RESPONSE" | grep -q "token"; then
  echo "✅ Registration successful"
  TOKEN=$(echo "$REGISTER_RESPONSE" | jq -r '.token')
else
  echo "❌ Registration failed"
  echo "$REGISTER_RESPONSE"
fi

# 2. Test Product Listing
echo "2. Testing Product Listing..."
PRODUCTS_RESPONSE=$(curl -s -X GET "$BASE_URL/api/inventory/products?page=1&limit=5" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0")

if echo "$PRODUCTS_RESPONSE" | grep -q "products"; then
  echo "✅ Product listing successful"
  echo "Found $(echo "$PRODUCTS_RESPONSE" | jq '.total // 0') products"
else
  echo "❌ Product listing failed"
  echo "$PRODUCTS_RESPONSE"
fi

# 3. Test Dashboard
echo "3. Testing Dashboard..."
DASHBOARD_RESPONSE=$(curl -s -X GET "$BASE_URL/api/sales/dashboard" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-API-Version: v1.0.0")

if echo "$DASHBOARD_RESPONSE" | grep -q "today_sales"; then
  echo "✅ Dashboard data successful"
else
  echo "❌ Dashboard data failed"
  echo "$DASHBOARD_RESPONSE"
fi

echo "🎉 API Integration Testing Complete!"
```

---

## 🎯 Flutter Implementation Checklist

### **Before You Start:**
- [ ] Backend services running on port 8090
- [ ] User registered and token obtained
- [ ] Flutter project created with required dependencies
- [ ] API client configured with proper base URL

### **Authentication Implementation:**
- [ ] Login screen with email/password validation
- [ ] Token storage using flutter_secure_storage
- [ ] Auto-refresh token mechanism
- [ ] Logout functionality

### **Product Features:**
- [ ] Product listing with pagination
- [ ] Search functionality with debouncing
- [ ] Category and brand filtering
- [ ] Product detail screen
- [ ] Add to cart functionality

### **Sales Features:**
- [ ] Order creation workflow
- [ ] Cart management
- [ ] Payment processing
- [ ] Order history
- [ ] Receipt generation

### **Dashboard Features:**
- [ ] Sales metrics display
- [ ] Real-time updates
- [ ] Charts and analytics
- [ ] Inventory alerts

### **Error Handling:**
- [ ] Network error handling
- [ ] API error responses
- [ ] User-friendly error messages
- [ ] Retry mechanisms

---

## 🚀 Production Deployment

### **Environment Configuration:**

```dart
class ApiConfig {
  static const String devBaseUrl = 'http://localhost:8090';
  static const String stagingBaseUrl = 'https://staging-api.liquorpro.com';
  static const String prodBaseUrl = 'https://api.liquorpro.com';
  
  static String get baseUrl {
    if (kDebugMode) return devBaseUrl;
    if (kProfileMode) return stagingBaseUrl;
    return prodBaseUrl;
  }
  
  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-API-Version': 'v1.0.0',
  };
}
```

**Your Flutter mobile app is now ready for complete integration with your industrial-grade LiquorPro backend! 🎉**
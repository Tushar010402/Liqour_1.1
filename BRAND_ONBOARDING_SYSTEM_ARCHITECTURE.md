# 🏗️ Brand Onboarding System Architecture

## Overview
LiquorPro has a **two-tier brand management system** designed for maximum flexibility and ease of use:

1. **SaaS Admin Brands** (Global Templates) - Pre-defined by super admin
2. **Tenant Custom Brands** - Created/modified by individual tenants

---

## 🌐 Tier 1: SaaS Admin Brands (Global Templates)

### Purpose
- **Centralized Brand Management**: Super admin creates brand templates with categories, subcategories, and variants
- **Quick Onboarding**: Tenants can instantly onboard pre-configured brands
- **Consistency**: Ensures standardized brand information across all tenants
- **Reduced Setup Time**: Eliminates need for tenants to manually enter common brand data

### Database Structure
```
SaaS Service (Port 8095)
├── saas_brands (Brand templates)
│   ├── id, name, description, picture
│   ├── is_active, sort_order
│   └── created_at, updated_at
├── brand_categories (e.g., Whiskey, Vodka, Beer)
│   ├── id, name, description
│   └── is_active, sort_order
├── brand_subcategories (e.g., Premium, Ultra Premium)
│   ├── id, name, category_id
│   └── price_range, description
├── brand_variants (Size & price variations)
│   ├── id, brand_id, category_id, subcategory_id
│   ├── size (750ml, 1L, etc.)
│   ├── alcohol_content, picture, barcode, hsn_code
│   ├── government_duty, buying_price, selling_price, mrp
│   └── is_active, sort_order
└── tenant_brands (Assignments)
    ├── id, tenant_id, brand_id
    └── is_active
```

### Key APIs (SaaS Service)
```go
// Super Admin APIs
GET    /api/super-admin/brands                    // Get all SaaS brands
GET    /api/super-admin/brands/:id                 // Get brand with variants
POST   /api/super-admin/brands                    // Create new brand
PUT    /api/super-admin/brands/:id                // Update brand
DELETE /api/super-admin/brands/:id                // Delete brand

GET    /api/super-admin/brands/:id/variants       // Get brand variants
POST   /api/super-admin/brands/variants           // Create variant
PUT    /api/super-admin/brands/variants/:id       // Update variant
DELETE /api/super-admin/brands/variants/:id       // Delete variant

GET    /api/super-admin/brands/categories         // Get categories
POST   /api/super-admin/brands/categories         // Create category
GET    /api/super-admin/brands/subcategories      // Get subcategories
POST   /api/super-admin/brands/subcategories      // Create subcategory

// Tenant Assignment
POST   /api/super-admin/brands/assign             // Assign brands to tenant
GET    /api/super-admin/tenants/:id/brands        // Get tenant's assigned brands

// Public/Onboarding APIs
GET    /api/brands/public                         // Get all available brands (for onboarding)
GET    /api/super-admin/brands/packages           // Get preset brand packages
POST   /api/super-admin/brands/assign-package     // Assign package to tenant
```

### Brand Packages (Quick Onboarding)
```json
{
  "starter": {
    "name": "Starter Package",
    "description": "Essential brands for new stores",
    "brand_count": 3,
    "brands": ["Brand A", "Brand B", "Brand C"]
  },
  "premium": {
    "name": "Premium Package",
    "description": "Popular brands for established stores",
    "brand_count": 6
  },
  "full": {
    "name": "Complete Package",
    "description": "All available brands",
    "brand_count": 20+
  }
}
```

---

## 🏪 Tier 2: Tenant Inventory (Custom Brands)

### Purpose
- **Flexibility**: Tenants can create their own unique brands
- **Customization**: Modify SaaS-onboarded brands with custom pricing/info
- **Full Control**: Tenants manage their own inventory independently

### Database Structure
```
Inventory Service (Port 8093)
├── brands (Tenant-specific brands)
│   ├── id, tenant_id, name, description
│   └── is_active, created_at, updated_at
├── categories (Tenant categories)
│   ├── id, tenant_id, name, description
│   └── is_active, sort_order
├── products (Tenant products)
│   ├── id, tenant_id, brand_id, category_id
│   ├── name, size, barcode, sku
│   ├── cost_price, duty_fee, total_cost
│   ├── selling_price, mrp
│   ├── alcohol_content, description, image_url
│   └── is_active
└── stocks (Per-shop inventory)
    ├── id, tenant_id, shop_id, product_id
    ├── quantity, reserved_quantity
    ├── minimum_level, maximum_level
    └── average_cost, last_purchase_price
```

### Key APIs (Inventory Service)
```go
// Brand Onboarding (from SaaS templates)
GET  /api/inventory/saas-brands/available         // Get available SaaS brands
POST /api/inventory/saas-brands/onboard           // Onboard selected brands
GET  /api/inventory/saas-brands/onboarded         // Get onboarded brands
PUT  /api/inventory/saas-brands/onboarded/:id     // Customize onboarded brand

// Custom Brand Management
GET    /api/inventory/brands/custom               // Get custom brands
POST   /api/inventory/brands                      // Create custom brand
PUT    /api/inventory/brands/:id                  // Update brand
DELETE /api/inventory/brands/:id                  // Delete brand

// Product Management
GET    /api/inventory/products                    // List products (onboarded + custom)
POST   /api/inventory/products                    // Create product
GET    /api/inventory/products/:id                // Get product
PUT    /api/inventory/products/:id                // Update product
DELETE /api/inventory/products/:id                // Delete product

// Categories
GET    /api/inventory/categories                  // List categories
POST   /api/inventory/categories                  // Create category
PUT    /api/inventory/categories/:id              // Update category
DELETE /api/inventory/categories/:id              // Delete category

// Stock Management
GET    /api/inventory/stock                       // Get stock levels
POST   /api/inventory/stock/adjust                // Adjust stock
POST   /api/inventory/purchases                   // Create purchase order
```

---

## 🔄 Brand Onboarding Flow

### Step 1: SaaS Admin Setup (One-time)
```
Super Admin creates SaaS brands:
1. Create categories (Whiskey, Vodka, Beer, etc.)
2. Create subcategories (Premium, Ultra Premium, Basic)
3. Create brands (Johnnie Walker, Absolut, etc.)
4. Create variants (750ml-₹2000, 1L-₹3000, etc.)
```

### Step 2: Tenant Onboarding (Quick Start)
```
Tenant onboards brands into inventory:
1. Browse available SaaS brand templates
2. Select brands/variants to onboard
3. System auto-creates:
   - Brands in tenant's inventory
   - Categories (if not exist)
   - Products with pre-filled data
```

### Step 3: Customization (Optional)
```
Tenant customizes onboarded data:
1. Update prices (cost, selling, MRP)
2. Modify descriptions
3. Add/edit images
4. Set shop-specific stock levels
```

### Step 4: Custom Brands (Anytime)
```
Tenant creates unique brands:
1. Add brand not in SaaS templates
2. Create products manually
3. Full control over all fields
```

---

## 📊 Data Sync Architecture

```
┌─────────────────┐           ┌───────────────────┐
│   SaaS Service  │           │ Inventory Service │
│   (Port 8095)   │           │    (Port 8093)    │
└────────┬────────┘           └────────┬──────────┘
         │                              │
         │  1. GET /api/brands/public   │
         │◄─────────────────────────────┤
         │                              │
         │  2. Return brand templates   │
         ├─────────────────────────────►│
         │                              │
         │                              │ 3. Tenant selects brands
         │                              │
         │                              │ 4. Create brands/products
         │                              │    in tenant_id context
         │                              │
         │  5. Notify sync (optional)   │
         │◄─────────────────────────────┤
         │                              │
```

---

## 🎯 User Experience Flow

### For Tenants (Flutter App)
```
1. Inventory Tab
   ├── Quick Start Button
   │   ├── "Onboard Popular Brands" (Opens onboarding wizard)
   │   └── Shows: Starter, Premium, Full packages
   │
   ├── Onboarded Brands Tab
   │   ├── Shows products from SaaS templates
   │   ├── Badge: "From Template"
   │   └── Can customize pricing/info
   │
   ├── Custom Brands Tab
   │   ├── Shows tenant-created brands
   │   ├── Badge: "Custom"
   │   └── Full CRUD operations
   │
   └── All Products View
       ├── Combined list (onboarded + custom)
       ├── Search & Filters
       └── Stock levels per shop
```

### Onboarding Wizard
```
Screen 1: Browse Templates
├── Categories filter
├── Brand cards with images
├── Variant details (sizes, prices)
└── Select multiple brands

Screen 2: Review Selection
├── Selected brands summary
├── Total variants: 24
├── Customize prices (optional)
└── Confirm onboarding

Screen 3: Success
├── "15 brands onboarded successfully"
├── "42 products created"
└── "Go to Inventory" button
```

---

## 🔐 Security & Permissions

### SaaS Admin
- Full CRUD on brand templates
- Can assign brands to any tenant
- Manages categories/subcategories
- Hard delete capability

### Tenant Admin
- View available SaaS brands
- Onboard selected brands
- Full CRUD on custom brands
- Customize onboarded data
- Cannot modify SaaS templates

### Tenant Users (Shop Managers)
- View products only
- Update stock levels
- Create sales/purchases
- No brand/category management

---

## 💡 Key Benefits

### For SaaS Provider
✅ Centralized brand data management
✅ Easy tenant onboarding
✅ Reduced support tickets
✅ Consistent data quality

### For Tenants
✅ Instant setup (seconds vs hours)
✅ Pre-filled brand information
✅ Professional product catalog
✅ Flexibility to customize
✅ Can add unique products

### Technical Benefits
✅ Separation of concerns
✅ Scalable architecture
✅ Independent services
✅ Easy maintenance
✅ Clear data ownership

---

## 🚀 Implementation Status

✅ SaaS Admin Brand Management
✅ Brand Categories & Subcategories
✅ Brand Variants with Pricing
✅ Tenant Brand Assignment
✅ Inventory Onboarding Service
✅ Custom Brand Creation
✅ Product CRUD Operations
✅ Stock Management

🔄 In Progress
- Flutter UI for brand onboarding
- Visual brand selection wizard
- Package-based onboarding

---

## 📱 Flutter Implementation Plan

### Models Needed
```dart
- SaasBrand (template)
- SaasBrandVariant (template variant)
- BrandCategory
- BrandSubcategory
- Product (tenant product)
- Brand (tenant brand)
- Stock (inventory levels)
```

### Services Needed
```dart
- BrandOnboardingService (fetch SaaS brands, onboard)
- ProductService (CRUD tenant products)
- CategoryService (manage categories)
- StockService (inventory management)
```

### UI Screens
```dart
1. BrandOnboardingScreen (wizard)
2. ProductsListScreen (all products)
3. ProductDetailScreen
4. ProductFormScreen (create/edit)
5. StockManagementScreen
6. CategoryManagementScreen
```

---

**Last Updated**: October 4, 2025
**Architecture Version**: 2.0
**Status**: Production Ready ✅

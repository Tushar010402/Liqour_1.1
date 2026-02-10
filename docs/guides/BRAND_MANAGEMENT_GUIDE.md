# LiquorPro Brand Management System

## Overview

The enhanced brand management system allows SaaS admins to create predefined brands with detailed specifications that tenants can select from. Each brand includes government duty, pricing, size, pictures, categories, and subcategories.

## Architecture Components

### 1. SaaS Brand Models (`internal/saas/models/brand.go`)

#### Core Models:
- **SaasBrand**: Master brand definition
- **BrandVariant**: Specific variants of brands (sizes, types)
- **TenantBrand**: Brands selected by tenants
- **TenantBrandVariant**: Specific variants selected by tenants

#### Key Features:
- Predefined brand catalog
- Government duty per piece
- Buying/selling price suggestions
- Size specifications (750ml, 1L, etc.)
- High-quality product images
- Category/subcategory classification
- HSN codes for tax compliance

### 2. SaaS Brand Service (`internal/saas/services/brand_service.go`)

#### Core Functions:
- `CreateBrand()`: Create new master brands
- `CreateBrandVariant()`: Add variants to brands
- `GetAllBrands()`: Get all available brands
- `AssignBrandsToTenant()`: Assign brands to specific tenants
- `GetTenantBrands()`: Get brands assigned to tenant

### 3. SaaS Brand Handler (`internal/saas/handlers/brand_handler.go`)

#### API Endpoints:
- `POST /api/super-admin/brands` - Create brand
- `POST /api/super-admin/brands/variants` - Create brand variant
- `GET /api/super-admin/brands` - Get all brands
- `GET /api/brands/public` - Public brands for tenant selection
- `POST /api/super-admin/brands/assign` - Assign brands to tenant

### 4. Tenant Brand Integration (`internal/inventory/services/tenant_brand_service.go`)

#### Core Functions:
- `GetAvailableBrands()`: Get brands from SaaS service
- `GetTenantBrands()`: Get tenant's assigned brands
- `CreateProductFromBrandVariant()`: Create inventory products from brand variants
- `SyncBrandVariantPricing()`: Sync pricing updates

## API Endpoints

### SaaS Admin Endpoints

#### Create Brand
```bash
POST /api/super-admin/brands
```
```json
{
  "name": "Johnnie Walker",
  "description": "Premium Scotch Whisky",
  "picture": "https://example.com/johnnie-walker-logo.jpg",
  "is_active": true,
  "sort_order": 1
}
```

#### Create Brand Variant
```bash
POST /api/super-admin/brands/variants
```
```json
{
  "brand_id": "550e8400-e29b-41d4-a716-446655440000",
  "category_id": "550e8400-e29b-41d4-a716-446655440001",
  "subcategory_id": "550e8400-e29b-41d4-a716-446655440002",
  "size": "750ml",
  "alcohol_content": 40.0,
  "picture": "https://example.com/johnnie-walker-black-750ml.jpg",
  "government_duty": 150.00,
  "buying_price": 2500.00,
  "selling_price": 3000.00,
  "mrp": 3500.00,
  "description": "Johnnie Walker Black Label 750ml",
  "barcode": "1234567890123",
  "hsn_code": "2208.30.90",
  "is_active": true,
  "sort_order": 1
}
```

#### Assign Brands to Tenant
```bash
POST /api/super-admin/brands/assign
```
```json
{
  "tenant_id": "550e8400-e29b-41d4-a716-446655440003",
  "brand_ids": ["550e8400-e29b-41d4-a716-446655440000"],
  "variant_ids": ["550e8400-e29b-41d4-a716-446655440004"]
}
```

#### Get All Brands (with variants)
```bash
GET /api/super-admin/brands?include_variants=true
```

#### Bulk Create Brands
```bash
POST /api/super-admin/brands/bulk
```
```json
[
  {
    "brand": {
      "name": "Royal Challenge",
      "description": "Premium Indian Whisky",
      "picture": "https://example.com/royal-challenge.jpg",
      "is_active": true
    },
    "variants": [
      {
        "category_id": "whisky-category-id",
        "size": "750ml",
        "government_duty": 120.00,
        "buying_price": 1800.00,
        "selling_price": 2200.00,
        "mrp": 2500.00
      }
    ]
  }
]
```

### Tenant Endpoints

#### Get Available Brands
```bash
GET /api/brands/available?include_variants=true
```

#### Get Tenant's Selected Brands
```bash
GET /api/brands/my-brands
```

#### Create Product from Brand Variant
```bash
POST /api/brands/create-product
```
```json
{
  "variant_id": "550e8400-e29b-41d4-a716-446655440004",
  "shop_id": "550e8400-e29b-41d4-a716-446655440005"
}
```

#### Sync Brand Pricing
```bash
POST /api/brands/sync-pricing
```

## Usage Workflow

### For SaaS Admin:

1. **Create Master Brands**
   ```bash
   POST /api/super-admin/brands
   ```

2. **Add Brand Variants**
   ```bash
   POST /api/super-admin/brands/variants
   ```

3. **Assign Brands to Tenants**
   ```bash
   POST /api/super-admin/brands/assign
   ```

### For Tenants:

1. **Browse Available Brands**
   ```bash
   GET /api/brands/available
   ```

2. **View Assigned Brands**
   ```bash
   GET /api/brands/my-brands
   ```

3. **Create Products from Brands**
   ```bash
   POST /api/brands/create-product
   ```

4. **Sync Latest Pricing**
   ```bash
   POST /api/brands/sync-pricing
   ```

## Database Schema

### SaaS Brand Tables
- `saas_brands` - Master brand definitions
- `brand_variants` - Brand variants with pricing
- `tenant_brands` - Tenant brand selections
- `tenant_brand_variants` - Tenant variant selections

### Key Fields:
- **Government Duty**: Per-piece duty amount
- **Buying Price**: Suggested purchase price
- **Selling Price**: Suggested retail price
- **MRP**: Maximum Retail Price
- **Size**: Product size (750ml, 1L, etc.)
- **Picture**: High-quality product image URL
- **HSN Code**: Tax classification code
- **Barcode**: Standard product barcode

## Features

### ✅ Brand Catalog Management
- Create and manage master brand catalog
- Add detailed specifications and imagery
- Categorize by liquor types

### ✅ Variant Management
- Multiple sizes per brand
- Alcohol content specifications
- Government duty calculations
- Comprehensive pricing structure

### ✅ Tenant Selection
- Optional brand selection for tenants
- Tenant-specific customizations
- Bulk brand assignment

### ✅ Inventory Integration
- Direct product creation from brand variants
- Automated pricing synchronization
- Stock management integration

### ✅ Pricing Management
- Government duty per piece
- Buying price suggestions
- Selling price recommendations
- MRP compliance

### ✅ Compliance Features
- HSN code integration
- Barcode management
- Tax calculation support

## Benefits

1. **Standardization**: Consistent product data across tenants
2. **Efficiency**: Quick product setup from predefined brands
3. **Compliance**: Built-in tax and regulatory information
4. **Scalability**: Central brand management for multiple tenants
5. **Accuracy**: Reduced data entry errors
6. **Updates**: Centralized pricing and information updates

## Migration

The system includes automatic database migrations for:
- SaaS brand models
- Tenant brand relationships
- Pricing structures
- Category associations

Run the SaaS service to automatically create the required tables.

## Testing

Test the brand management system using the provided API endpoints:

1. Create sample brands as SaaS admin
2. Assign brands to test tenants
3. Create products from brand variants
4. Verify pricing synchronization

This enhanced brand management system provides a complete solution for managing liquor brands with government compliance, detailed specifications, and tenant flexibility.
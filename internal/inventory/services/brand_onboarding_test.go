package services

import (
	"testing"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"go.uber.org/zap"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

// MockSaaSBrandClient mocks the SaaS brand client
type MockSaaSBrandClient struct {
	mock.Mock
}

func (m *MockSaaSBrandClient) GetAllBrandTemplates(includeVariants bool) ([]SaaSBrandTemplate, error) {
	args := m.Called(includeVariants)
	return args.Get(0).([]SaaSBrandTemplate), args.Error(1)
}

func (m *MockSaaSBrandClient) GetBrandTemplate(brandID uuid.UUID) (*SaaSBrandTemplate, error) {
	args := m.Called(brandID)
	return args.Get(0).(*SaaSBrandTemplate), args.Error(1)
}

func (m *MockSaaSBrandClient) GetCategories() ([]SaaSCategory, error) {
	args := m.Called()
	return args.Get(0).([]SaaSCategory), args.Error(1)
}

func (m *MockSaaSBrandClient) GetSubcategories() ([]SaaSSubcategory, error) {
	args := m.Called()
	return args.Get(0).([]SaaSSubcategory), args.Error(1)
}

// setupTestDB creates an in-memory SQLite database for testing
func setupTestDB(t *testing.T) *gorm.DB {
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	assert.NoError(t, err)

	// Auto-migrate test tables
	err = db.AutoMigrate(
		&models.Product{},
		&models.Brand{},
		&models.Category{},
	)
	assert.NoError(t, err)

	return db
}

// TestDuplicatePreventionOnboarding tests that duplicate variants are skipped
func TestDuplicatePreventionOnboarding(t *testing.T) {
	db := setupTestDB(t)
	logger := zap.NewNop()

	// Create mock SaaS client
	mockClient := new(MockSaaSBrandClient)

	// Setup test data
	tenantID := uuid.New()
	brandID := uuid.New()
	variantID := uuid.New()
	categoryID := uuid.New()

	category := &SaaSCategory{
		ID:          categoryID,
		Name:        "Whisky",
		Description: "Premium Whisky",
		IsActive:    true,
		SortOrder:   1,
	}

	brandTemplate := &SaaSBrandTemplate{
		ID:          brandID,
		Name:        "Test Brand",
		Description: "Test Description",
		IsActive:    true,
		BrandVariants: []SaaSBrandVariant{
			{
				ID:             variantID,
				BrandID:        brandID,
				CategoryID:     categoryID,
				Size:           "750ml",
				AlcoholContent: 40.0,
				BuyingPrice:    1000.0,
				SellingPrice:   1200.0,
				MRP:            1300.0,
				GovernmentDuty: 200.0,
				Category:       category,
				IsActive:       true,
			},
		},
	}

	// Mock the GetBrandTemplate call
	mockClient.On("GetBrandTemplate", brandID).Return(brandTemplate, nil)

	// Create service
	service := &BrandOnboardingService{
		db:         db,
		saasClient: mockClient,
		logger:     logger,
	}

	// First onboarding - should create product
	request := OnboardBrandRequest{
		TenantID: tenantID,
		BrandIDs: []uuid.UUID{brandID},
	}

	response1, err := service.OnboardBrandsToTenant(request)
	assert.NoError(t, err)
	assert.Equal(t, 1, response1.OnboardedBrands)
	assert.Equal(t, 1, response1.OnboardedProducts)
	assert.Len(t, response1.BrandDetails, 1)
	assert.True(t, response1.BrandDetails[0].Success)
	assert.Equal(t, 1, response1.BrandDetails[0].ProductsCreated)

	// Verify product was created with SaaS tracking
	var product models.Product
	err = db.Where("tenant_id = ?", tenantID).First(&product).Error
	assert.NoError(t, err)
	assert.NotNil(t, product.SaaSBrandID)
	assert.NotNil(t, product.SaaSVariantID)
	assert.Equal(t, brandID, *product.SaaSBrandID)
	assert.Equal(t, variantID, *product.SaaSVariantID)

	// Second onboarding - should skip duplicate
	response2, err := service.OnboardBrandsToTenant(request)
	assert.NoError(t, err)
	assert.Equal(t, 0, response2.OnboardedBrands) // No new brands
	assert.Equal(t, 0, response2.OnboardedProducts) // No new products
	assert.Len(t, response2.BrandDetails, 1)
	assert.False(t, response2.BrandDetails[0].Success) // Marked as unsuccessful
	assert.Equal(t, 0, response2.BrandDetails[0].ProductsCreated)

	// Verify only one product exists
	var productCount int64
	db.Model(&models.Product{}).Where("tenant_id = ?", tenantID).Count(&productCount)
	assert.Equal(t, int64(1), productCount)

	mockClient.AssertExpectations(t)
}

// TestMultipleTenantsSameBrand tests that different tenants can onboard the same brand
func TestMultipleTenantsSameBrand(t *testing.T) {
	db := setupTestDB(t)
	logger := zap.NewNop()

	mockClient := new(MockSaaSBrandClient)

	// Setup test data
	tenant1ID := uuid.New()
	tenant2ID := uuid.New()
	brandID := uuid.New()
	variantID := uuid.New()
	categoryID := uuid.New()

	category := &SaaSCategory{
		ID:          categoryID,
		Name:        "Whisky",
		Description: "Premium Whisky",
		IsActive:    true,
		SortOrder:   1,
	}

	brandTemplate := &SaaSBrandTemplate{
		ID:          brandID,
		Name:        "Test Brand",
		Description: "Test Description",
		IsActive:    true,
		BrandVariants: []SaaSBrandVariant{
			{
				ID:             variantID,
				BrandID:        brandID,
				CategoryID:     categoryID,
				Size:           "750ml",
				AlcoholContent: 40.0,
				BuyingPrice:    1000.0,
				SellingPrice:   1200.0,
				MRP:            1300.0,
				GovernmentDuty: 200.0,
				Category:       category,
				IsActive:       true,
			},
		},
	}

	mockClient.On("GetBrandTemplate", brandID).Return(brandTemplate, nil)

	service := &BrandOnboardingService{
		db:         db,
		saasClient: mockClient,
		logger:     logger,
	}

	// Tenant 1 onboards
	request1 := OnboardBrandRequest{
		TenantID: tenant1ID,
		BrandIDs: []uuid.UUID{brandID},
	}
	response1, err := service.OnboardBrandsToTenant(request1)
	assert.NoError(t, err)
	assert.Equal(t, 1, response1.OnboardedProducts)

	// Tenant 2 onboards same brand - should succeed
	request2 := OnboardBrandRequest{
		TenantID: tenant2ID,
		BrandIDs: []uuid.UUID{brandID},
	}
	response2, err := service.OnboardBrandsToTenant(request2)
	assert.NoError(t, err)
	assert.Equal(t, 1, response2.OnboardedProducts)

	// Verify both tenants have products
	var tenant1ProductCount int64
	db.Model(&models.Product{}).Where("tenant_id = ?", tenant1ID).Count(&tenant1ProductCount)
	assert.Equal(t, int64(1), tenant1ProductCount)

	var tenant2ProductCount int64
	db.Model(&models.Product{}).Where("tenant_id = ?", tenant2ID).Count(&tenant2ProductCount)
	assert.Equal(t, int64(1), tenant2ProductCount)

	mockClient.AssertExpectations(t)
}

// TestCategoryCreationTracking tests that categories_created is correctly counted
func TestCategoryCreationTracking(t *testing.T) {
	db := setupTestDB(t)
	logger := zap.NewNop()

	mockClient := new(MockSaaSBrandClient)

	tenantID := uuid.New()
	brand1ID := uuid.New()
	brand2ID := uuid.New()
	category1ID := uuid.New()
	category2ID := uuid.New()

	category1 := &SaaSCategory{
		ID:          category1ID,
		Name:        "Whisky",
		Description: "Whisky products",
		IsActive:    true,
		SortOrder:   1,
	}

	category2 := &SaaSCategory{
		ID:          category2ID,
		Name:        "Rum",
		Description: "Rum products",
		IsActive:    true,
		SortOrder:   2,
	}

	// Brand 1 with Whisky category
	brandTemplate1 := &SaaSBrandTemplate{
		ID:   brand1ID,
		Name: "Brand 1",
		BrandVariants: []SaaSBrandVariant{
			{
				ID:             uuid.New(),
				BrandID:        brand1ID,
				CategoryID:     category1ID,
				Size:           "750ml",
				AlcoholContent: 40.0,
				BuyingPrice:    1000.0,
				SellingPrice:   1200.0,
				MRP:            1300.0,
				GovernmentDuty: 200.0,
				Category:       category1,
				IsActive:       true,
			},
		},
	}

	// Brand 2 with Rum category
	brandTemplate2 := &SaaSBrandTemplate{
		ID:   brand2ID,
		Name: "Brand 2",
		BrandVariants: []SaaSBrandVariant{
			{
				ID:             uuid.New(),
				BrandID:        brand2ID,
				CategoryID:     category2ID,
				Size:           "1L",
				AlcoholContent: 42.0,
				BuyingPrice:    800.0,
				SellingPrice:   1000.0,
				MRP:            1100.0,
				GovernmentDuty: 150.0,
				Category:       category2,
				IsActive:       true,
			},
		},
	}

	mockClient.On("GetBrandTemplate", brand1ID).Return(brandTemplate1, nil)
	mockClient.On("GetBrandTemplate", brand2ID).Return(brandTemplate2, nil)

	service := &BrandOnboardingService{
		db:         db,
		saasClient: mockClient,
		logger:     logger,
	}

	// Onboard both brands
	request := OnboardBrandRequest{
		TenantID: tenantID,
		BrandIDs: []uuid.UUID{brand1ID, brand2ID},
	}

	response, err := service.OnboardBrandsToTenant(request)
	assert.NoError(t, err)
	assert.Equal(t, 2, response.OnboardedBrands)
	assert.Equal(t, 2, response.OnboardedProducts)
	assert.Equal(t, 2, response.CategoriesCreated) // Both categories created

	mockClient.AssertExpectations(t)
}

// TestPartialVariantOnboarding tests onboarding specific variants only
func TestPartialVariantOnboarding(t *testing.T) {
	db := setupTestDB(t)
	logger := zap.NewNop()

	mockClient := new(MockSaaSBrandClient)

	tenantID := uuid.New()
	brandID := uuid.New()
	variant1ID := uuid.New()
	variant2ID := uuid.New()
	categoryID := uuid.New()

	category := &SaaSCategory{
		ID:   categoryID,
		Name: "Whisky",
	}

	brandTemplate := &SaaSBrandTemplate{
		ID:   brandID,
		Name: "Test Brand",
		BrandVariants: []SaaSBrandVariant{
			{
				ID:             variant1ID,
				BrandID:        brandID,
				CategoryID:     categoryID,
				Size:           "750ml",
				AlcoholContent: 40.0,
				BuyingPrice:    1000.0,
				SellingPrice:   1200.0,
				MRP:            1300.0,
				GovernmentDuty: 200.0,
				Category:       category,
				IsActive:       true,
			},
			{
				ID:             variant2ID,
				BrandID:        brandID,
				CategoryID:     categoryID,
				Size:           "1L",
				AlcoholContent: 40.0,
				BuyingPrice:    1800.0,
				SellingPrice:   2000.0,
				MRP:            2200.0,
				GovernmentDuty: 300.0,
				Category:       category,
				IsActive:       true,
			},
		},
	}

	mockClient.On("GetBrandTemplate", brandID).Return(brandTemplate, nil)

	service := &BrandOnboardingService{
		db:         db,
		saasClient: mockClient,
		logger:     logger,
	}

	// Onboard only variant1
	request := OnboardBrandRequest{
		TenantID:   tenantID,
		BrandIDs:   []uuid.UUID{brandID},
		VariantIDs: []uuid.UUID{variant1ID}, // Only one variant
	}

	response, err := service.OnboardBrandsToTenant(request)
	assert.NoError(t, err)
	assert.Equal(t, 1, response.OnboardedBrands)
	assert.Equal(t, 1, response.OnboardedProducts) // Only 1 product created

	// Verify only variant1 was onboarded
	var product models.Product
	err = db.Where("saas_variant_id = ?", variant1ID).First(&product).Error
	assert.NoError(t, err)

	// Verify variant2 was not onboarded
	err = db.Where("saas_variant_id = ?", variant2ID).First(&product).Error
	assert.Error(t, err) // Should not exist

	mockClient.AssertExpectations(t)
}

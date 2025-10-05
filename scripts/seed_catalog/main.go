package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func main() {
	// Database connection
	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		getEnv("DATABASE_HOST", "localhost"),
		getEnv("DATABASE_PORT", "5432"),
		getEnv("DATABASE_USER", "liquorpro"),
		getEnv("DATABASE_PASSWORD", "liquorpro_password"),
		getEnv("DATABASE_NAME", "liquorpro"))

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}

	// Run migrations first
	err = models.MigrateDB(db)
	if err != nil {
		log.Fatal("Failed to migrate database:", err)
	}

	// Seed data
	if err := seedProductCatalog(db); err != nil {
		log.Fatal("Failed to seed product catalog:", err)
	}

	fmt.Println("Product catalog seeded successfully!")
}

func seedProductCatalog(db *gorm.DB) error {
	// Define tenant IDs to seed
	tenantIDs := []string{
		"373e965a-6dec-44d6-a2ab-0400449fc71d", // Trinket Beverages tenant
		"a1e56607-af5c-4196-b445-b0d0b064e182", // Add tenant
	}

	for _, tenantID := range tenantIDs {
		fmt.Printf("Seeding product catalog for tenant: %s\n", tenantID)

		// Get the specific tenant by ID
		var tenant models.Tenant
		if err := db.Where("id = ?", tenantID).First(&tenant).Error; err != nil {
			fmt.Printf("Warning: failed to find tenant %s: %v\n", tenantID, err)
			continue
		}

		if err := seedForTenant(db, tenant); err != nil {
			return fmt.Errorf("failed to seed for tenant %s: %w", tenantID, err)
		}
	}

	return nil
}

func seedForTenant(db *gorm.DB, tenant models.Tenant) error {
	// Check if data already exists for this tenant
	var existingCount int64
	db.Model(&models.Category{}).Where("tenant_id = ?", tenant.ID).Count(&existingCount)
	if existingCount > 0 {
		fmt.Printf("Data already exists for tenant %s, skipping...\n", tenant.ID)
		return nil
	}

	// Create categories
	categories := []models.Category{
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Whiskey",
			Description: "Premium whiskey collection",
			SortOrder:   1,
			IsActive:    true,
		},
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Vodka",
			Description: "Premium vodka selection",
			SortOrder:   2,
			IsActive:    true,
		},
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Beer",
			Description: "Beer and lager collection",
			SortOrder:   3,
			IsActive:    true,
		},
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Rum",
			Description: "Premium rum collection",
			SortOrder:   4,
			IsActive:    true,
		},
	}

	for _, category := range categories {
		if err := db.FirstOrCreate(&category, models.Category{Name: category.Name}).Error; err != nil {
			return fmt.Errorf("failed to create category %s: %w", category.Name, err)
		}
	}

	// Create subcategories
	subcategories := []models.Subcategory{
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Ultra Premium",
			CategoryID:  categories[0].ID, // Whiskey
			PriceRange:  "Ultra Premium",
			Description: "Ultra premium whiskey collection",
			SortOrder:   1,
			IsActive:    true,
		},
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Premium",
			CategoryID:  categories[0].ID, // Whiskey
			PriceRange:  "Premium",
			Description: "Premium whiskey collection",
			SortOrder:   2,
			IsActive:    true,
		},
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Premium",
			CategoryID:  categories[1].ID, // Vodka
			PriceRange:  "Premium",
			Description: "Premium vodka collection",
			SortOrder:   1,
			IsActive:    true,
		},
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Normal",
			CategoryID:  categories[2].ID, // Beer
			PriceRange:  "Normal",
			Description: "Regular beer collection",
			SortOrder:   1,
			IsActive:    true,
		},
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Premium",
			CategoryID:  categories[3].ID, // Rum
			PriceRange:  "Premium",
			Description: "Premium rum collection",
			SortOrder:   1,
			IsActive:    true,
		},
	}

	for _, subcategory := range subcategories {
		if err := db.FirstOrCreate(&subcategory, models.Subcategory{
			Name:       subcategory.Name,
			CategoryID: subcategory.CategoryID,
		}).Error; err != nil {
			return fmt.Errorf("failed to create subcategory %s: %w", subcategory.Name, err)
		}
	}

	// Create brands
	brands := []models.Brand{
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Johnnie Walker",
			Description: "Premium Scotch whisky brand",
			IsActive:    true,
		},
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Absolut",
			Description: "Premium vodka brand",
			IsActive:    true,
		},
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Kingfisher",
			Description: "Popular beer brand",
			IsActive:    true,
		},
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Bacardi",
			Description: "Premium rum brand",
			IsActive:    true,
		},
		{
			TenantModel: models.TenantModel{BaseModel: models.BaseModel{ID: uuid.New()}, TenantID: tenant.ID},
			Name:        "Royal Challenge",
			Description: "Premium whiskey brand",
			IsActive:    true,
		},
	}

	for _, brand := range brands {
		if err := db.FirstOrCreate(&brand, models.Brand{Name: brand.Name}).Error; err != nil {
			return fmt.Errorf("failed to create brand %s: %w", brand.Name, err)
		}
	}

	// Create product templates with sample images
	sizeOptions750ml, _ := json.Marshal([]string{"750ml"})
	sizeOptions330ml, _ := json.Marshal([]string{"330ml", "650ml"})
	sizeOptions180ml, _ := json.Marshal([]string{"180ml", "375ml", "750ml"})

	templates := []models.ProductTemplate{
		{
			BaseModel:      models.BaseModel{ID: uuid.New()},
			Name:           "Johnnie Walker Black Label",
			CategoryID:     categories[0].ID,     // Whiskey
			SubcategoryID:  &subcategories[0].ID, // Ultra Premium
			BrandID:        &brands[0].ID,        // Johnnie Walker
			ImageURL:       "https://images.unsplash.com/photo-1569529465841-dfecdab7503b?w=400&h=600&fit=crop&crop=center",
			Sizes:          string(sizeOptions750ml),
			DutyFeeRate:    0.15, // 15% duty fee
			IsStandard:     true,
			Description:    "Premium Scotch whisky with rich, complex flavors",
			AlcoholContent: 40.0,
			SortOrder:      1,
		},
		{
			BaseModel:      models.BaseModel{ID: uuid.New()},
			Name:           "Royal Challenge Whisky",
			CategoryID:     categories[0].ID,     // Whiskey
			SubcategoryID:  &subcategories[1].ID, // Premium
			BrandID:        &brands[4].ID,        // Royal Challenge
			ImageURL:       "https://images.unsplash.com/photo-1613748897041-9b7e0e56d5a8?w=400&h=600&fit=crop&crop=center",
			Sizes:          string(sizeOptions180ml),
			DutyFeeRate:    0.12, // 12% duty fee
			IsStandard:     true,
			Description:    "Smooth and refined Indian whisky",
			AlcoholContent: 42.8,
			SortOrder:      2,
		},
		{
			BaseModel:      models.BaseModel{ID: uuid.New()},
			Name:           "Absolut Vodka",
			CategoryID:     categories[1].ID,     // Vodka
			SubcategoryID:  &subcategories[2].ID, // Premium
			BrandID:        &brands[1].ID,        // Absolut
			ImageURL:       "https://images.unsplash.com/photo-1560472355-a9a2ab7e40d8?w=400&h=600&fit=crop&crop=center",
			Sizes:          string(sizeOptions750ml),
			DutyFeeRate:    0.10, // 10% duty fee
			IsStandard:     true,
			Description:    "Premium vodka with pure taste and quality",
			AlcoholContent: 40.0,
			SortOrder:      3,
		},
		{
			BaseModel:      models.BaseModel{ID: uuid.New()},
			Name:           "Kingfisher Beer",
			CategoryID:     categories[2].ID,     // Beer
			SubcategoryID:  &subcategories[3].ID, // Normal
			BrandID:        &brands[2].ID,        // Kingfisher
			ImageURL:       "https://images.unsplash.com/photo-1608270586620-248524c67de9?w=400&h=600&fit=crop&crop=center",
			Sizes:          string(sizeOptions330ml),
			DutyFeeRate:    0.05, // 5% duty fee
			IsStandard:     true,
			Description:    "Popular Indian lager beer",
			AlcoholContent: 5.0,
			SortOrder:      4,
		},
		{
			BaseModel:      models.BaseModel{ID: uuid.New()},
			Name:           "Bacardi White Rum",
			CategoryID:     categories[3].ID,     // Rum
			SubcategoryID:  &subcategories[4].ID, // Premium
			BrandID:        &brands[3].ID,        // Bacardi
			ImageURL:       "https://images.unsplash.com/photo-1589487391730-58f20eb2c308?w=400&h=600&fit=crop&crop=center",
			Sizes:          string(sizeOptions750ml),
			DutyFeeRate:    0.12, // 12% duty fee
			IsStandard:     true,
			Description:    "Premium white rum for cocktails and mixing",
			AlcoholContent: 37.5,
			SortOrder:      5,
		},
	}

	for _, template := range templates {
		if err := db.FirstOrCreate(&template, models.ProductTemplate{Name: template.Name}).Error; err != nil {
			return fmt.Errorf("failed to create product template %s: %w", template.Name, err)
		}
	}

	fmt.Println("Created categories:", len(categories))
	fmt.Println("Created subcategories:", len(subcategories))
	fmt.Println("Created brands:", len(brands))
	fmt.Println("Created product templates:", len(templates))

	return nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

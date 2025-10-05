package main

import (
	"fmt"
	"log"
	"os"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
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

	// Create Tenant and Admin User
	if err := createTenantAndAdmin(db); err != nil {
		log.Fatal("Failed to create tenant admin:", err)
	}

	fmt.Println("Tenant Admin created successfully!")
}

func createTenantAndAdmin(db *gorm.DB) error {
	// Admin User details
	phone := "+918126816664"
	email := "admin@demo-tenant.com"
	username := "tenant_admin_8126816664"
	firstName := "Tenant"
	lastName := "Admin"
	tenantName := "Demo Tenant"

	// Check if user already exists
	var existingUser models.User
	if err := db.Where("phone = ? OR email = ? OR username = ?", phone, email, username).First(&existingUser).Error; err == nil {
		fmt.Printf("User already exists: %s\n", existingUser.Email)
		return nil
	}

	// First, create or find a tenant
	var tenant models.Tenant
	err := db.Where("name = ?", tenantName).First(&tenant).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			// Create new tenant
			tenant = models.Tenant{
				Name:     tenantName,
				IsActive: true,
			}
			tenant.ID = uuid.New()

			if err := db.Create(&tenant).Error; err != nil {
				return fmt.Errorf("failed to create tenant: %w", err)
			}
			fmt.Printf("Created tenant: %s\n", tenant.Name)
		} else {
			return fmt.Errorf("failed to query tenant: %w", err)
		}
	}

	// Hash default password
	hashedPassword, err := utils.HashPassword("TenantAdmin@2024")
	if err != nil {
		return fmt.Errorf("failed to hash password: %w", err)
	}

	// Create Tenant Admin User
	tenantAdmin := models.User{
		Username:     username,
		Email:        email,
		FirstName:    firstName,
		LastName:     lastName,
		Phone:        phone,
		PasswordHash: hashedPassword,
		Role:         models.RoleAdmin, // Admin role
		IsActive:     true,
		IsStaff:      false,
		IsSuperuser:  false,
		TenantID:     &tenant.ID, // Assign to tenant
	}
	tenantAdmin.ID = uuid.New()

	if err := db.Create(&tenantAdmin).Error; err != nil {
		return fmt.Errorf("failed to create tenant admin: %w", err)
	}

	fmt.Printf("Created Tenant Admin: %s (%s) with role: %s for tenant: %s\n",
		tenantAdmin.Email, tenantAdmin.Phone, tenantAdmin.Role, tenant.Name)
	return nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

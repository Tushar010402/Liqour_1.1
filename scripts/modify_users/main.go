package main

import (
	"fmt"
	"log"
	"os"

	"github.com/google/uuid"
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

	// Modify users table and create Super User
	if err := modifyUsersTable(db); err != nil {
		log.Fatal("Failed to modify users table:", err)
	}

	if err := createSuperUser(db); err != nil {
		log.Fatal("Failed to create super user:", err)
	}

	fmt.Println("Database migration and Super User creation completed successfully!")
}

func modifyUsersTable(db *gorm.DB) error {
	fmt.Println("Modifying users table to allow NULL tenant_id for Super Users...")

	// Step 1: Drop the NOT NULL constraint on tenant_id
	result := db.Exec("ALTER TABLE users ALTER COLUMN tenant_id DROP NOT NULL")
	if result.Error != nil {
		return fmt.Errorf("failed to drop NOT NULL constraint on tenant_id: %w", result.Error)
	}

	fmt.Println("✓ Dropped NOT NULL constraint on tenant_id")
	return nil
}

func createSuperUser(db *gorm.DB) error {
	// Super User details
	phone := "+918630668488"
	email := "dharam.prakash@liquorpro.com"
	username := "dharam_prakash"
	firstName := "Dharam"
	lastName := "Prakash"
	userID := uuid.New()

	// Check if Super User already exists
	var count int64
	db.Raw("SELECT COUNT(*) FROM users WHERE phone = ? OR email = ? OR username = ?", phone, email, username).Scan(&count)
	if count > 0 {
		fmt.Printf("Super User already exists, updating...\n")

		// Update existing user
		result := db.Exec(`
			UPDATE users 
			SET role = 'saas_admin', is_superuser = true, is_staff = true, is_active = true, tenant_id = NULL 
			WHERE phone = ? OR email = ? OR username = ?
		`, phone, email, username)

		if result.Error != nil {
			return fmt.Errorf("failed to update existing super user: %w", result.Error)
		}

		fmt.Printf("✓ Updated existing Super User to SaaS admin role\n")
		return nil
	}

	// Hash default password
	hashedPassword, err := utils.HashPassword("SuperAdmin@2024")
	if err != nil {
		return fmt.Errorf("failed to hash password: %w", err)
	}

	// Create Super User with NULL tenant_id
	result := db.Exec(`
		INSERT INTO users (id, created_at, updated_at, tenant_id, username, email, first_name, last_name, phone, password_hash, role, is_active, is_staff, is_superuser, custom_role, profile_image)
		VALUES (?, NOW(), NOW(), NULL, ?, ?, ?, ?, ?, ?, 'saas_admin', true, true, true, '', '')
	`, userID, username, email, firstName, lastName, phone, hashedPassword)

	if result.Error != nil {
		return fmt.Errorf("failed to create super user: %w", result.Error)
	}

	fmt.Printf("✓ Created Super User: %s (%s) with role: saas_admin\n", email, phone)
	fmt.Printf("✓ Super User ID: %s\n", userID)
	fmt.Printf("✓ Default password: SuperAdmin@2024\n")
	fmt.Printf("✓ Special OTP for %s: 111111\n", phone)
	return nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

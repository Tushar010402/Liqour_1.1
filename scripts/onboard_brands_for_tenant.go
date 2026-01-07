package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"

	"github.com/google/uuid"
	_ "github.com/lib/pq"
)

func main() {
	// Get tenant ID from command line argument
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run onboard_brands_for_tenant.go <tenant_id>")
		fmt.Println("Or use 'ALL' to onboard all 39 brands for a tenant")
		os.Exit(1)
	}

	tenantID := os.Args[1]

	// Database connection
	dbHost := os.Getenv("DATABASE_HOST")
	if dbHost == "" {
		dbHost = "postgres"
	}
	dbUser := os.Getenv("DATABASE_USER")
	if dbUser == "" {
		dbUser = "liquorpro_prod"
	}
	dbPassword := os.Getenv("DATABASE_PASSWORD")
	if dbPassword == "" {
		dbPassword = "b4fb1ea26df2dafe05e75975723e8102def013a339b8c18262bdde8a0ef8e6d2"
	}
	dbName := os.Getenv("DATABASE_NAME")
	if dbName == "" {
		dbName = "liquorpro_production"
	}

	connStr := fmt.Sprintf("host=%s user=%s password=%s dbname=%s sslmode=disable",
		dbHost, dbUser, dbPassword, dbName)

	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer db.Close()

	// Verify tenant exists
	var tenantExists bool
	err = db.QueryRow("SELECT EXISTS(SELECT 1 FROM tenants WHERE id = $1)", tenantID).Scan(&tenantExists)
	if err != nil || !tenantExists {
		log.Fatal("Invalid tenant ID or tenant does not exist")
	}

	fmt.Printf("Onboarding brands for tenant: %s\n", tenantID)

	// Begin transaction
	tx, err := db.Begin()
	if err != nil {
		log.Fatal("Failed to begin transaction:", err)
	}
	defer tx.Rollback()

	// Get all master brands
	query := `
		SELECT id, name FROM saas_brands
		WHERE is_active = true
		ORDER BY sort_order
	`
	rows, err := tx.Query(query)
	if err != nil {
		log.Fatal("Failed to fetch brands:", err)
	}
	defer rows.Close()

	brandCount := 0
	variantCount := 0

	for rows.Next() {
		var brandID uuid.UUID
		var brandName string

		err := rows.Scan(&brandID, &brandName)
		if err != nil {
			log.Printf("Error scanning brand: %v", err)
			continue
		}

		// Create tenant brand
		tenantBrandID := uuid.New()
		_, err = tx.Exec(`
			INSERT INTO tenant_brands (id, tenant_id, brand_id, is_active, activated_at, created_at, updated_at)
			VALUES ($1, $2, $3, true, NOW(), NOW(), NOW())
			ON CONFLICT (tenant_id, brand_id) DO UPDATE SET is_active = true, updated_at = NOW()
		`, tenantBrandID, tenantID, brandID)

		if err != nil {
			log.Printf("Error creating tenant brand for %s: %v", brandName, err)
			continue
		}

		// Get variants for this brand
		variantRows, err := tx.Query(`
			SELECT id, size, government_duty, buying_price, selling_price, mrp
			FROM brand_variants
			WHERE brand_id = $1 AND is_active = true
		`, brandID)
		if err != nil {
			log.Printf("Error fetching variants for %s: %v", brandName, err)
			continue
		}

		for variantRows.Next() {
			var variantID uuid.UUID
			var size string
			var duty, buyingPrice, sellingPrice, mrp float64

			err := variantRows.Scan(&variantID, &size, &duty, &buyingPrice, &sellingPrice, &mrp)
			if err != nil {
				log.Printf("Error scanning variant: %v", err)
				continue
			}

			// Create tenant brand variant
			_, err = tx.Exec(`
				INSERT INTO tenant_brand_variants (
					id, tenant_brand_id, brand_variant_id,
					custom_buying_price, custom_selling_price, custom_mrp,
					is_active, activated_at, created_at, updated_at
				) VALUES ($1, $2, $3, $4, $5, $6, true, NOW(), NOW(), NOW())
				ON CONFLICT DO NOTHING
			`, uuid.New(), tenantBrandID, variantID, buyingPrice, sellingPrice, mrp)

			if err != nil {
				log.Printf("Error creating tenant variant: %v", err)
				continue
			}

			variantCount++
		}
		variantRows.Close()

		brandCount++
		fmt.Printf("✓ Onboarded: %s\n", brandName)
	}

	// Commit transaction
	err = tx.Commit()
	if err != nil {
		log.Fatal("Failed to commit transaction:", err)
	}

	fmt.Printf("\n=== Onboarding Complete ===\n")
	fmt.Printf("Brands onboarded: %d\n", brandCount)
	fmt.Printf("Variants onboarded: %d\n", variantCount)
	fmt.Printf("Tenant %s can now use all 39 master brands!\n", tenantID)
}
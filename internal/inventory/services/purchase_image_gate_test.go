//go:build image_gate
// +build image_gate

// AI-Purchase image gate (2026-05-18). Run with:
//
//	go test -tags=image_gate ./internal/inventory/services/
//
// Behind its own build tag to match this package's convention (every suite
// is tag-gated so a pre-existing broken suite never blocks the default
// build). Locks the contract that ONLY products created by AI Stock Setup
// (created_via='stock_setup') with no image at all are gated, and that the
// legacy_exempt default + every other origin are exempt (strictly
// forward-only — zero disruption to the existing backlog).
//
// The gate predicate is exercised against a minimal hand-built `products`
// table rather than GORM AutoMigrate of the real models: those models carry
// Postgres-only column defaults (now() / gen_random_uuid()) sqlite cannot
// parse. The CREATE TABLE below mirrors migration
// 20260518_products_created_via.sql (created_via NOT NULL DEFAULT
// 'legacy_exempt') so the default-exempt behaviour is validated too. The
// GORM model<->column mapping itself is covered by `go build`, the explicit
// gorm:"column:created_via" tag, and production Postgres.
package services

import (
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func imageGateTestDB(t *testing.T) *gorm.DB {
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	require.NoError(t, err)
	// Mirror of migration 20260518_products_created_via.sql — only the
	// columns the gate touches. created_via carries the forward-only
	// exempt default.
	require.NoError(t, db.Exec(`
		CREATE TABLE products (
			id              TEXT PRIMARY KEY,
			tenant_id       TEXT,
			name            TEXT,
			created_via     TEXT NOT NULL DEFAULT 'legacy_exempt',
			image_url       TEXT,
			front_image_url TEXT,
			back_image_url  TEXT,
			deleted_at      DATETIME
		)`).Error)
	return db
}

func TestPurchaseImageRequiredError_Error(t *testing.T) {
	e := &PurchaseImageRequiredError{Products: []ImageRequiredProduct{
		{ID: uuid.New(), Name: "8 PM Premium Black - 750ml"},
		{ID: uuid.New(), Name: "Old Monk - 180ml"},
	}}
	msg := e.Error()
	assert.Contains(t, msg, "2 product(s)")
	assert.Contains(t, msg, "8 PM Premium Black - 750ml")
	assert.Contains(t, msg, "Old Monk - 180ml")
}

// TestImageGate_StockSetupOnly proves the EXACT gate predicate used in
// smart_purchase_apply.go:ApplySmartPurchase (kept in sync here — it is a
// pure WHERE clause). A product is flagged iff:
//
//	created_via = 'stock_setup'  AND
//	image_url, front_image_url, back_image_url ALL empty.
func TestImageGate_StockSetupOnly(t *testing.T) {
	db := imageGateTestDB(t)
	tid := uuid.New().String()

	mk := func(name, createdVia, img, front, back string) string {
		id := uuid.New().String()
		require.NoError(t, db.Exec(
			`INSERT INTO products (id, tenant_id, name, created_via, image_url, front_image_url, back_image_url)
			 VALUES (?, ?, ?, ?, ?, ?, ?)`,
			id, tid, name, createdVia, img, front, back).Error)
		return id
	}

	gatedStockSetupNoImage := mk("8PM - 750ml", "stock_setup", "", "", "")
	stockSetupWithFront := mk("Old Monk - 180ml", "stock_setup", "", "https://x/f.jpg", "")
	stockSetupWithBack := mk("RC - 750ml", "stock_setup", "", "", "https://x/b.jpg")
	stockSetupWithImageURL := mk("Imperial - 375ml", "stock_setup", "https://x/i.jpg", "", "")
	legacyNoImage := mk("Legacy - 750ml", "legacy_exempt", "", "", "")
	aiPurchaseNoImage := mk("AIP - 750ml", "ai_purchase", "", "", "")
	manualNoImage := mk("Manual - 750ml", "manual", "", "", "")

	allIDs := []string{
		gatedStockSetupNoImage, stockSetupWithFront, stockSetupWithBack,
		stockSetupWithImageURL, legacyNoImage, aiPurchaseNoImage, manualNoImage,
	}

	// Verbatim mirror of the production gate query.
	var need []ImageRequiredProduct
	require.NoError(t, db.Table("products").
		Select("id, name").
		Where(`tenant_id = ? AND id IN ? AND deleted_at IS NULL
		        AND created_via = ?
		        AND COALESCE(image_url,'') = ''
		        AND COALESCE(front_image_url,'') = ''
		        AND COALESCE(back_image_url,'') = ''`,
			tid, allIDs, "stock_setup").
		Scan(&need).Error)

	require.Len(t, need, 1, "only the image-less stock_setup product must be gated")
	assert.Equal(t, gatedStockSetupNoImage, need[0].ID.String())
	assert.Equal(t, "8PM - 750ml", need[0].Name)

	// The DEFAULT column value is the exempt sentinel, so a row created with
	// no explicit created_via is NEVER gated (fail-open / forward-only).
	defID := uuid.New().String()
	require.NoError(t, db.Exec(
		`INSERT INTO products (id, tenant_id, name) VALUES (?, ?, ?)`,
		defID, tid, "NoCreatedVia - 750ml").Error)
	var createdVia string
	require.NoError(t, db.Raw(
		`SELECT created_via FROM products WHERE id = ?`, defID).Scan(&createdVia).Error)
	assert.Equal(t, "legacy_exempt", createdVia,
		"unstamped products must default to legacy_exempt")

	var defNeed []ImageRequiredProduct
	require.NoError(t, db.Table("products").
		Select("id, name").
		Where(`tenant_id = ? AND id = ? AND deleted_at IS NULL
		        AND created_via = ?
		        AND COALESCE(image_url,'') = ''
		        AND COALESCE(front_image_url,'') = ''
		        AND COALESCE(back_image_url,'') = ''`,
			tid, defID, "stock_setup").
		Scan(&defNeed).Error)
	assert.Empty(t, defNeed, "legacy_exempt default row must not be gated")
}

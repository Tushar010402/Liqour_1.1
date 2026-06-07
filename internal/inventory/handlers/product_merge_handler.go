package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"gorm.io/gorm"
)

// ProductMergeHandler — Phase E. The OPT-IN, audited, all-or-nothing tool to
// consolidate the duplicate product rows surfaced by the Inventory "⧉ N"
// badge (Phase C) and stocksetup_dupe_audit.sh. It is NEVER automatic: the
// operator picks a canonical row + the duplicates to fold in, sees a
// mandatory dry-run preview, and only then commits.
//
// Safety, by design:
//   - HARD GUARD: refuses if the canonical and any duplicate have differing
//     non-null saas_brand_id, or differing shop_id — merging different
//     flavours/shops is exactly the data damage the operator fears. brand_id
//     is COARSE and is deliberately NOT used.
//   - Atomic: all repoints + stock-sum + soft-deletes happen in ONE
//     transaction; ANY error rolls the WHOLE thing back (no partial merge)
//     and returns a structured non-2xx (truthful contract, like v1.0.279).
//   - Audited + reversible: a stock_histories row (movement_type
//     'product_merge') records the full mapping + per-table counts.
type ProductMergeHandler struct {
	db *database.DB
}

func NewProductMergeHandler(db *database.DB) *ProductMergeHandler {
	return &ProductMergeHandler{db: db}
}

// Every live table carrying a product_id that must follow the merge. `stocks`
// is handled separately (summed, not blindly repointed). Enumerated from
// information_schema on 2026-05-17; keep in sync if a new product_id column
// is added (the dupe-audit / a schema test should flag drift).
var productMergeRepointTables = []string{
	"audit_variances", "daily_sales_items", "inventory_audit_items",
	"ocr_brand_aliases", "sale_items", "sale_return_items",
	"shrinkage_records", "stock_audit_logs", "stock_histories",
	"stock_purchase_items", "stock_update_requests",
	"stock_verification_items", "product_change_requests",
	"shop_product_rates", "smart_sale_rescue_drops", "stock_batches",
	"stock_setup_items",
}

type productMergeRequest struct {
	CanonicalID  string   `json:"canonical_id"`
	DuplicateIDs []string `json:"duplicate_ids"`
	DryRun       bool     `json:"dry_run"`
}

type mergeProductInfo struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Size        string `json:"size"`
	SaasBrandID string `json:"saas_brand_id"`
	ShopID      string `json:"shop_id"`
	Stock       int    `json:"stock"`
}

type productMergeResult struct {
	DryRun         bool               `json:"dry_run"`
	Canonical      mergeProductInfo   `json:"canonical"`
	Duplicates     []mergeProductInfo `json:"duplicates"`
	StockBefore    int                `json:"stock_before"`     // canonical only
	StockAfter     int                `json:"stock_after"`      // canonical + all dups
	RepointCounts  map[string]int     `json:"repoint_counts"`   // table -> rows that (will) move
	DeletedCount   int                `json:"deleted_count"`    // duplicate products soft-deleted
	ImagesBackfilled int              `json:"images_backfilled,omitempty"` // faces (front/back) copied from a dup
	Message        string             `json:"message"`
	AuditReference string             `json:"audit_reference,omitempty"`
}

// MergeProducts handles POST /products/merge.
func (h *ProductMergeHandler) MergeProducts(c *gin.Context) {
	tenantStr, ok := c.Get("tenant_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing tenant"})
		return
	}
	tenantID, err := uuid.Parse(tenantStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant ID"})
		return
	}
	var createdBy uuid.UUID
	if uid, ok := c.Get("user_id"); ok {
		createdBy, _ = uuid.Parse(uid.(string))
	}

	var req productMergeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	canonicalID, err := uuid.Parse(req.CanonicalID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid canonical_id"})
		return
	}
	if len(req.DuplicateIDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no duplicate_ids supplied"})
		return
	}
	dupIDs := make([]uuid.UUID, 0, len(req.DuplicateIDs))
	for _, d := range req.DuplicateIDs {
		du, perr := uuid.Parse(d)
		if perr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid duplicate id " + d})
			return
		}
		if du == canonicalID {
			c.JSON(http.StatusBadRequest, gin.H{"error": "canonical_id cannot also be a duplicate"})
			return
		}
		dupIDs = append(dupIDs, du)
	}

	type pRow struct {
		ID          uuid.UUID
		Name        string
		Size        string
		SaasBrandID *uuid.UUID `gorm:"column:saas_brand_id"`
		ShopID      *uuid.UUID `gorm:"column:shop_id"`
		DeletedAt   *time.Time `gorm:"column:deleted_at"`
	}
	loadRows := func(ids []uuid.UUID) ([]pRow, error) {
		var rows []pRow
		e := h.db.Table("products").
			Select("id, name, size, saas_brand_id, shop_id, deleted_at").
			Where("tenant_id = ? AND id IN ?", tenantID, ids).
			Scan(&rows).Error
		return rows, e
	}

	canonRows, err := loadRows([]uuid.UUID{canonicalID})
	if err != nil || len(canonRows) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "canonical product not found in this tenant"})
		return
	}
	canon := canonRows[0]
	if canon.DeletedAt != nil {
		c.JSON(http.StatusUnprocessableEntity, gin.H{"error": "canonical product is deleted"})
		return
	}
	dupRows, err := loadRows(dupIDs)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if len(dupRows) != len(dupIDs) {
		c.JSON(http.StatusNotFound, gin.H{"error": "one or more duplicate products not found in this tenant"})
		return
	}

	// ---- HARD SAFETY GUARDS (refuse cross-flavour / cross-shop merges) ----
	sbStr := func(u *uuid.UUID) string {
		if u == nil {
			return ""
		}
		return u.String()
	}
	for _, d := range dupRows {
		if canon.SaasBrandID != nil && d.SaasBrandID != nil &&
			*canon.SaasBrandID != *d.SaasBrandID {
			c.JSON(http.StatusUnprocessableEntity, gin.H{
				"error": fmt.Sprintf("refused: '%s' and '%s' have different saas_brand_id (different products) — merge blocked", canon.Name, d.Name),
				"code":  "different_saas_brand",
			})
			return
		}
		if sbStr(canon.ShopID) != sbStr(d.ShopID) {
			c.JSON(http.StatusUnprocessableEntity, gin.H{
				"error": fmt.Sprintf("refused: '%s' and '%s' belong to different shops — merge blocked", canon.Name, d.Name),
				"code":  "different_shop",
			})
			return
		}
	}

	stockOf := func(pid uuid.UUID) int {
		var q struct{ Q int }
		_ = h.db.Table("stocks").
			Select("COALESCE(SUM(quantity),0) AS q").
			Where("tenant_id = ? AND product_id = ? AND deleted_at IS NULL", tenantID, pid).
			Scan(&q).Error
		return q.Q
	}
	toInfo := func(r pRow) mergeProductInfo {
		return mergeProductInfo{
			ID: r.ID.String(), Name: r.Name, Size: r.Size,
			SaasBrandID: sbStr(r.SaasBrandID), ShopID: sbStr(r.ShopID),
			Stock: stockOf(r.ID),
		}
	}

	result := productMergeResult{
		DryRun:        req.DryRun,
		Canonical:     toInfo(canon),
		RepointCounts: map[string]int{},
	}
	result.StockBefore = result.Canonical.Stock
	sumStock := result.Canonical.Stock
	for _, d := range dupRows {
		di := toInfo(d)
		result.Duplicates = append(result.Duplicates, di)
		sumStock += di.Stock
	}
	result.StockAfter = sumStock
	result.DeletedCount = len(dupRows)

	// Per-table count of rows that point at a duplicate (preview + audit).
	for _, tbl := range productMergeRepointTables {
		var cnt int64
		if e := h.db.Table(tbl).Where("product_id IN ?", dupIDs).Count(&cnt).Error; e == nil {
			if cnt > 0 {
				result.RepointCounts[tbl] = int(cnt)
			}
		}
	}

	if req.DryRun {
		result.Message = fmt.Sprintf("DRY RUN — would fold %d duplicate(s) into '%s', stock %d → %d. Nothing changed.",
			len(dupRows), canon.Name, result.StockBefore, result.StockAfter)
		c.JSON(http.StatusOK, result)
		return
	}

	// ---------------- COMMIT (atomic: all or nothing) ----------------
	auditID := uuid.New()
	txErr := h.db.Transaction(func(tx *gorm.DB) error {
		// 1) Repoint every product_id table from dups → canonical.
		for _, tbl := range productMergeRepointTables {
			if e := tx.Exec(
				fmt.Sprintf("UPDATE %s SET product_id = ? WHERE product_id IN ?", tbl),
				canonicalID, dupIDs).Error; e != nil {
				return fmt.Errorf("repoint %s failed: %w", tbl, e)
			}
		}
		// 1.5) v1.0.350 — preserve product photos. A duplicate may hold the only
		// front/back label image; the merge must not drop it. Back-fill each face
		// onto the canonical ONLY when the canonical lacks it, from the first
		// duplicate that has one (deterministic by name,id). Images are columns on
		// products, so this is a plain column backfill — no child-table repoint.
		{
			type imgRow struct {
				FrontImageURL          string   `gorm:"column:front_image_url"`
				BackImageURL           string   `gorm:"column:back_image_url"`
				BackImageMRP           float64  `gorm:"column:back_image_mrp"`
				BackImageMRPConfidence *float64 `gorm:"column:back_image_mrp_confidence"`
				VerifiedViaImageFront  bool     `gorm:"column:verified_via_image_front"`
				VerifiedViaImageBack   bool     `gorm:"column:verified_via_image_back"`
			}
			var canonImg imgRow
			if e := tx.Table("products").
				Select("front_image_url, back_image_url, back_image_mrp, back_image_mrp_confidence, verified_via_image_front, verified_via_image_back").
				Where("id = ?", canonicalID).Scan(&canonImg).Error; e != nil {
				return fmt.Errorf("merge: load canonical images failed: %w", e)
			}
			updates := map[string]interface{}{}
			if canonImg.FrontImageURL == "" {
				var d imgRow
				if e := tx.Table("products").
					Select("front_image_url, verified_via_image_front").
					Where("tenant_id = ? AND id IN ? AND COALESCE(front_image_url,'') <> ''", tenantID, dupIDs).
					Order("name ASC, id ASC").Limit(1).Scan(&d).Error; e == nil && d.FrontImageURL != "" {
					updates["front_image_url"] = d.FrontImageURL
					updates["verified_via_image_front"] = d.VerifiedViaImageFront
				}
			}
			if canonImg.BackImageURL == "" {
				var d imgRow
				if e := tx.Table("products").
					Select("back_image_url, back_image_mrp, back_image_mrp_confidence, verified_via_image_back").
					Where("tenant_id = ? AND id IN ? AND COALESCE(back_image_url,'') <> ''", tenantID, dupIDs).
					Order("name ASC, id ASC").Limit(1).Scan(&d).Error; e == nil && d.BackImageURL != "" {
					updates["back_image_url"] = d.BackImageURL
					updates["verified_via_image_back"] = d.VerifiedViaImageBack
					if d.BackImageMRP > 0 {
						updates["back_image_mrp"] = d.BackImageMRP
						if d.BackImageMRPConfidence != nil {
							updates["back_image_mrp_confidence"] = *d.BackImageMRPConfidence
						}
					}
				}
			}
			if _, ok := updates["front_image_url"]; ok {
				result.ImagesBackfilled++
			}
			if _, ok := updates["back_image_url"]; ok {
				result.ImagesBackfilled++
			}
			if len(updates) > 0 {
				updates["photo_verified_at"] = gorm.Expr("COALESCE(photo_verified_at, now())")
				updates["updated_at"] = gorm.Expr("now()")
				if e := tx.Table("products").Where("id = ?", canonicalID).Updates(updates).Error; e != nil {
					return fmt.Errorf("merge: backfill canonical images failed: %w", e)
				}
			}
		}
		// 2) Sum stock into the canonical's stock row (same shop, already
		//    guaranteed by the guard). Keep canonical's row; fold the rest.
		var canonStockID uuid.UUID
		var hasCanon bool
		{
			var s struct {
				ID uuid.UUID
			}
			e := tx.Table("stocks").Select("id").
				Where("tenant_id = ? AND product_id = ? AND deleted_at IS NULL", tenantID, canonicalID).
				Order("quantity DESC").Limit(1).Scan(&s).Error
			if e == nil && s.ID != uuid.Nil {
				canonStockID, hasCanon = s.ID, true
			}
		}
		if hasCanon {
			if e := tx.Exec(
				`UPDATE stocks SET quantity = ?, updated_at = now() WHERE id = ?`,
				sumStock, canonStockID).Error; e != nil {
				return fmt.Errorf("set canonical stock failed: %w", e)
			}
			// Soft-delete every OTHER stock row now pointing at canonical
			// (the dup stock rows were repointed in step 1). Their quantities
			// were already summed into the canonical row above, so removing them
			// is an audited fold, not a loss — opt past the block_stock_delete_with_qty
			// guard for THIS transaction only (SET LOCAL = tx-scoped).
			if e := tx.Exec(`SET LOCAL liquorpro.allow_stock_delete = 'on'`).Error; e != nil {
				return fmt.Errorf("merge: enable stock-delete bypass failed: %w", e)
			}
			if e := tx.Exec(
				`UPDATE stocks SET deleted_at = now() WHERE tenant_id = ? AND product_id = ? AND id <> ? AND deleted_at IS NULL`,
				tenantID, canonicalID, canonStockID).Error; e != nil {
				return fmt.Errorf("fold dup stock rows failed: %w", e)
			}
		}
		// 3) Soft-delete the duplicate products.
		if e := tx.Exec(
			`UPDATE products SET deleted_at = now(), updated_at = now() WHERE tenant_id = ? AND id IN ?`,
			tenantID, dupIDs).Error; e != nil {
			return fmt.Errorf("soft-delete duplicates failed: %w", e)
		}
		// 4) Audit (reversible): full mapping + counts on a stock_histories
		//    row. StockID is NOT NULL — use the canonical's stock row when
		//    present, else a zero UUID is rejected, so only write when known.
		auditPayload, _ := json.Marshal(map[string]interface{}{
			"merge_id":       auditID.String(),
			"canonical_id":   canonicalID.String(),
			"duplicate_ids":  req.DuplicateIDs,
			"repoint_counts": result.RepointCounts,
			"stock_before":   result.StockBefore,
			"stock_after":    result.StockAfter,
		})
		if hasCanon {
			cid := canonicalID
			sid := canonicalID // ProductID
			if e := tx.Exec(
				`INSERT INTO stock_histories
				 (id, created_at, updated_at, tenant_id, stock_id, shop_id, product_id,
				  movement_type, quantity, previous_quantity, new_quantity,
				  reference, reference_id, notes, created_by_id)
				 VALUES (?, now(), now(), ?, ?, ?, ?, 'product_merge', ?, ?, ?, ?, ?, ?, ?)`,
				uuid.New(), tenantID, canonStockID, canon.ShopID, cid,
				result.StockAfter-result.StockBefore, result.StockBefore, result.StockAfter,
				"product_merge:"+auditID.String(), sid, string(auditPayload), createdBy,
			).Error; e != nil {
				return fmt.Errorf("merge audit write failed: %w", e)
			}
		}
		return nil
	})
	if txErr != nil {
		// Atomic: nothing changed. Truthful non-2xx (mirrors v1.0.279).
		c.JSON(http.StatusUnprocessableEntity, gin.H{
			"error": "merge failed and was fully rolled back — nothing changed: " + txErr.Error(),
			"code":  "merge_rolled_back",
		})
		return
	}

	result.AuditReference = "product_merge:" + auditID.String()
	result.Message = fmt.Sprintf("Merged %d duplicate(s) into '%s'. Stock %d → %d. Fully audited (%s).",
		len(dupRows), canon.Name, result.StockBefore, result.StockAfter, result.AuditReference)
	c.JSON(http.StatusOK, result)
}

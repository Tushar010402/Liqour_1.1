package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
)

// AliasHygieneHandler provides admin endpoints to inspect + clean the
// per-tenant `ocr_brand_aliases` corpus. Lives separately from the main
// inventory handlers because it operates directly on the raw alias table
// rather than through the AliasService — this keeps it independent of any
// caching layer and lets the operator surgically retire/replace dirty
// entries that the matcher would otherwise trust forever.
//
// Real motivating case: the alias `100 strokes royal → Royal Challenge
// Select Premium` (occurrence_count 5) was a confirmed wrong canonical
// pick on 2026-04-30 that has been silently mis-routing every "100 strokes
// royal" handwritten read at FM Tower since. Pre-r8 there was no UI to
// retire it; admins had to drop into psql.
type AliasHygieneHandler struct {
	db *database.DB
}

func NewAliasHygieneHandler(db *database.DB) *AliasHygieneHandler {
	return &AliasHygieneHandler{db: db}
}

type aliasRow struct {
	ID                  uuid.UUID `json:"id"`
	AliasName           string    `json:"alias_name"`
	CanonicalBrandName  string    `json:"canonical_brand_name"`
	ProductID           *string   `json:"product_id,omitempty"`
	OccurrenceCount     int       `json:"occurrence_count"`
	ConfidenceScore     float64   `json:"confidence_score"`
	Source              string    `json:"source"`
	CreatedAt           string    `json:"created_at"`
	UpdatedAt           string    `json:"updated_at"`
	LastUsedAt          *string   `json:"last_used_at,omitempty"`
}

// ListConflicts returns alias_names that map to MULTIPLE different
// canonicals at this tenant. Each conflict cluster is emitted with the
// total occurrence count summed across the cluster — high-occurrence
// conflicts are the most damaging because they actively mis-route
// extractions today.
//
// Conflict signature: same `alias_name`, different `canonical_brand_name`
// or different `product_id`. We surface the full row set so the operator
// can see all candidates and choose which one is the truth.
func (h *AliasHygieneHandler) ListConflicts(c *gin.Context) {
	tenantIDRaw, ok := c.Get("tenant_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id missing"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDRaw.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant id"})
		return
	}

	type clusterRow struct {
		AliasName       string `json:"alias_name"`
		CanonicalCount  int    `json:"canonical_count"`
		TotalOccurrence int    `json:"total_occurrence"`
	}
	var clusters []clusterRow
	if err := h.db.Raw(`
		SELECT alias_name,
		       COUNT(DISTINCT canonical_brand_name) AS canonical_count,
		       SUM(occurrence_count) AS total_occurrence
		FROM ocr_brand_aliases
		WHERE tenant_id = ?
		  AND deleted_at IS NULL
		GROUP BY alias_name
		HAVING COUNT(DISTINCT canonical_brand_name) > 1
		ORDER BY SUM(occurrence_count) DESC
		LIMIT 100
	`, tenantID).Scan(&clusters).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// For each cluster, fetch the underlying rows so the UI can render
	// them grouped. Bounded by the LIMIT 100 above so we don't thrash.
	type clusterDetail struct {
		AliasName       string     `json:"alias_name"`
		CanonicalCount  int        `json:"canonical_count"`
		TotalOccurrence int        `json:"total_occurrence"`
		Rows            []aliasRow `json:"rows"`
	}
	out := make([]clusterDetail, 0, len(clusters))
	for _, cl := range clusters {
		var rows []aliasRow
		_ = h.db.Raw(`
			SELECT id, alias_name, canonical_brand_name, product_id::text AS product_id,
			       occurrence_count, confidence_score, source,
			       created_at::text AS created_at, updated_at::text AS updated_at,
			       last_used_at::text AS last_used_at
			FROM ocr_brand_aliases
			WHERE tenant_id = ? AND alias_name = ? AND deleted_at IS NULL
			ORDER BY occurrence_count DESC, last_used_at DESC NULLS LAST
		`, tenantID, cl.AliasName).Scan(&rows).Error
		out = append(out, clusterDetail{
			AliasName:       cl.AliasName,
			CanonicalCount:  cl.CanonicalCount,
			TotalOccurrence: cl.TotalOccurrence,
			Rows:            rows,
		})
	}
	c.JSON(http.StatusOK, gin.H{"clusters": out})
}

// ListLowConfidence returns aliases with occurrence_count < 3 — these are
// single-data-point learnings that the matcher already trusts as if they
// were canonical. The admin reviews them before they accumulate into
// "real" matches.
func (h *AliasHygieneHandler) ListLowConfidence(c *gin.Context) {
	tenantIDRaw, ok := c.Get("tenant_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id missing"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDRaw.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant id"})
		return
	}
	var rows []aliasRow
	if err := h.db.Raw(`
		SELECT id, alias_name, canonical_brand_name, product_id::text AS product_id,
		       occurrence_count, confidence_score, source,
		       created_at::text AS created_at, updated_at::text AS updated_at,
		       last_used_at::text AS last_used_at
		FROM ocr_brand_aliases
		WHERE tenant_id = ? AND deleted_at IS NULL AND occurrence_count < 3
		ORDER BY created_at DESC
		LIMIT 200
	`, tenantID).Scan(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"rows": rows})
}

// ListStale returns aliases that haven't been used by any extraction in
// 30+ days. Stale aliases either describe products the shop no longer
// stocks, or got typed wrong once and never fired again. Either way
// they're candidates for retirement so the corpus stays clean.
func (h *AliasHygieneHandler) ListStale(c *gin.Context) {
	tenantIDRaw, ok := c.Get("tenant_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id missing"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDRaw.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant id"})
		return
	}
	var rows []aliasRow
	if err := h.db.Raw(`
		SELECT id, alias_name, canonical_brand_name, product_id::text AS product_id,
		       occurrence_count, confidence_score, source,
		       created_at::text AS created_at, updated_at::text AS updated_at,
		       last_used_at::text AS last_used_at
		FROM ocr_brand_aliases
		WHERE tenant_id = ? AND deleted_at IS NULL
		  AND (last_used_at IS NULL OR last_used_at < NOW() - INTERVAL '30 days')
		  AND created_at < NOW() - INTERVAL '30 days'
		ORDER BY created_at ASC
		LIMIT 200
	`, tenantID).Scan(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"rows": rows})
}

// RetireAlias soft-deletes an alias by setting `deleted_at = NOW()`. The
// matcher's lookup excludes deleted_at IS NOT NULL rows, so the
// problematic mapping stops firing immediately. Caller passes the alias
// id (UUID) — checked against tenant scope so admins can't reach across
// tenants. Operation is per-row; for batch delete the UI fires multiple
// requests in parallel.
func (h *AliasHygieneHandler) RetireAlias(c *gin.Context) {
	tenantIDRaw, ok := c.Get("tenant_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id missing"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDRaw.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant id"})
		return
	}
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid alias id"})
		return
	}
	res := h.db.Exec(`
		UPDATE ocr_brand_aliases
		SET deleted_at = NOW(), updated_at = NOW()
		WHERE id = ? AND tenant_id = ? AND deleted_at IS NULL
	`, id, tenantID)
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
		return
	}
	if res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "alias not found or already retired"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"retired": id, "rows_affected": res.RowsAffected})
}

// MergeAliases keeps `keep_id` as the canonical row for `alias_name` and
// retires every OTHER row with the same alias_name at this tenant. Used
// by the conflict-cluster UI: operator picks the right canonical, taps
// Merge, and the bad rows are soft-deleted in one transaction.
//
// Body: { keep_id: "<uuid>" } — the row to preserve.
// URL param: :alias_name — the cluster being merged.
func (h *AliasHygieneHandler) MergeCluster(c *gin.Context) {
	tenantIDRaw, ok := c.Get("tenant_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id missing"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDRaw.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant id"})
		return
	}
	var body struct {
		AliasName string    `json:"alias_name" binding:"required"`
		KeepID    uuid.UUID `json:"keep_id"    binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "body must include alias_name + keep_id"})
		return
	}
	res := h.db.Exec(`
		UPDATE ocr_brand_aliases
		SET deleted_at = NOW(), updated_at = NOW()
		WHERE tenant_id = ? AND alias_name = ? AND id != ? AND deleted_at IS NULL
	`, tenantID, body.AliasName, body.KeepID)
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"alias_name":     body.AliasName,
		"kept":           body.KeepID,
		"retired_count":  res.RowsAffected,
	})
}

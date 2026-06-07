package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
)

// MissingSkuHandler walks the recent Smart Sale + Stock Setup job history
// and surfaces OCR texts that consistently came back as `not_found` —
// these are real brands the shopkeeper has but our master catalog
// doesn't. Pre-r8 there was no UI to find them; admins had to browse
// failed jobs by hand. The list is ranked by (occurrence × shop count)
// so the most-impactful gaps surface first.
//
// One-click "Add to master catalog" closes the gap permanently — once
// added, future extractions hit the master directly and the row stops
// being `not_found`. This is the long-tail companion to alias hygiene:
// alias-hygiene fixes wrong matches, missing-SKU fixes nothing-to-match.
type MissingSkuHandler struct {
	db *database.DB
}

func NewMissingSkuHandler(db *database.DB) *MissingSkuHandler {
	return &MissingSkuHandler{db: db}
}

type missingSkuRow struct {
	OCRText         string  `json:"ocr_text"`
	BrandName       string  `json:"brand_name"`
	Size            string  `json:"size"`
	Occurrences     int     `json:"occurrences"`
	DistinctShops   int     `json:"distinct_shops"`
	AvgRate         float64 `json:"avg_rate"`
	LastSeenAt      string  `json:"last_seen_at"`
	SampleJobID     string  `json:"sample_job_id"`
}

// List returns the top-N missing-SKU candidates for the current tenant,
// pulled from the last 30 days of Smart Sale + Stock Setup extraction
// history. Results are de-duplicated by lowercased OCR text and ranked
// by (occurrences × distinct_shops) so brands that hit multiple shops
// across multiple days bubble to the top.
//
// The query unions both extraction sources so we catch brands the shop
// stocked but never sold (Stock Setup not_found) and brands sold but not
// stocked (Smart Sale not_found from a one-off rare bottle).
func (h *MissingSkuHandler) List(c *gin.Context) {
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

	// We pull the full not_found set from both extraction job tables in
	// the last 30 days, group by lowercased ocr_text, and rank. The
	// jsonb_array_elements call is moderately heavy — bound to 30 days
	// to keep query cost predictable.
	var rows []missingSkuRow
	if err := h.db.Raw(`
		WITH not_found_rows AS (
			-- Smart Sale not_found extractions
			SELECT
			    LOWER(TRIM(item->>'ocr_text'))    AS ocr_text_norm,
			    item->>'ocr_text'                 AS ocr_text,
			    COALESCE(item->>'brand_name', '') AS brand_name,
			    COALESCE(item->>'size', '')       AS size,
			    j.shop_id::text                   AS shop_id,
			    COALESCE(NULLIF(item->>'rate','')::numeric, 0) AS rate,
			    j.id::text                        AS job_id,
			    j.created_at                      AS created_at
			FROM smart_sale_setup_jobs j,
			     jsonb_array_elements(j.result->'extracted_items') item
			WHERE j.tenant_id = ?
			  AND j.created_at > NOW() - INTERVAL '30 days'
			  AND jsonb_typeof(j.result->'extracted_items') = 'array'
			  AND item->>'validation_status' = 'not_found'
			  AND COALESCE(TRIM(item->>'ocr_text'), '') != ''
			UNION ALL
			-- Stock Setup not_found extractions
			SELECT
			    LOWER(TRIM(item->>'brand_name')) AS ocr_text_norm,
			    item->>'brand_name'              AS ocr_text,
			    COALESCE(item->>'brand_name','') AS brand_name,
			    COALESCE(item->>'size', '')      AS size,
			    j.shop_id::text                  AS shop_id,
			    COALESCE(NULLIF(item->>'rate','')::numeric, 0) AS rate,
			    j.id::text                       AS job_id,
			    j.created_at                     AS created_at
			FROM smart_stock_setup_jobs j,
			     jsonb_array_elements(j.result->'items') item
			WHERE j.tenant_id = ?
			  AND j.created_at > NOW() - INTERVAL '30 days'
			  AND jsonb_typeof(j.result->'items') = 'array'
			  AND item->>'status' = 'not_found'
			  AND COALESCE(TRIM(item->>'brand_name'), '') != ''
		)
		SELECT
		    MIN(ocr_text)        AS ocr_text,
		    MIN(brand_name)      AS brand_name,
		    MAX(size)            AS size,
		    COUNT(*)             AS occurrences,
		    COUNT(DISTINCT shop_id) AS distinct_shops,
		    AVG(NULLIF(rate, 0)) AS avg_rate,
		    MAX(created_at)::text AS last_seen_at,
		    MAX(job_id)          AS sample_job_id
		FROM not_found_rows
		WHERE ocr_text_norm IS NOT NULL AND ocr_text_norm != ''
		GROUP BY ocr_text_norm
		ORDER BY (COUNT(*) * COUNT(DISTINCT shop_id)) DESC, COUNT(*) DESC
		LIMIT 50
	`, tenantID, tenantID).Scan(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"rows":       rows,
		"window":     "30 days",
		"limit":      50,
		"hint":       "Add the top items to the master catalog (saas_brands) so future extractions match them. Brands with high occurrences × shops are the most impactful.",
	})
}

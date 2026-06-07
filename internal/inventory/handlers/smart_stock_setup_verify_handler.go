// v1.0.243 — Brand-image verify endpoint for AI Stock Setup.
//
// POST /stocks/smart-setup/verify-row
// Multipart form: photo (image), row_id (uuid), ocr_brand_text, ocr_size, shop_id, job_id (optional)
//
// Flow:
//   1. Save the photo to a stable path under /app/uploads/stock_setup/...
//   2. Pre-fetch ~8 master-brand candidates by token overlap with ocr_brand_text
//   3. If any candidate already has a reference image AND name == normalised ocr_text → CACHE HIT, skip Gemini
//   4. Else call GeminiBrandVerifier.Verify(photo, ocr_text, candidates)
//   5. Populate saas_brands.picture if missing (so next time is a cache hit)
//   6. Write ocr_brand_aliases row (raw OCR text → canonical brand, shop+tenant scope)
//   7. Insert stock_setup_image_verifications audit row
//   8. Return BrandVerificationResult + photo_url

package handlers

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png" // decoder registration so PNG captures normalize too
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/sirupsen/logrus"
	"golang.org/x/image/draw"
)

type SmartStockSetupVerifyHandler struct {
	verifier *services.GeminiBrandVerifier
	alias    *alias.AliasService
	db       *database.DB
	logger   *logrus.Logger
	// v1.0.355 — used to keep a product's tenant brand_id consistent with its
	// (photo-renamed) name. Optional: nil-safe (brand_id sync is skipped if unset).
	setupSvc *services.SmartStockSetupService
}

func NewSmartStockSetupVerifyHandler(
	verifier *services.GeminiBrandVerifier,
	aliasSvc *alias.AliasService,
	db *database.DB,
	logger *logrus.Logger,
	setupSvc *services.SmartStockSetupService,
) *SmartStockSetupVerifyHandler {
	return &SmartStockSetupVerifyHandler{
		verifier: verifier,
		alias:    aliasSvc,
		db:       db,
		logger:   logger,
		setupSvc: setupSvc,
	}
}

type verifyRowResponse struct {
	RowID            string  `json:"row_id"`
	CanonicalName    string  `json:"canonical_name"`
	MasterBrandID    string  `json:"master_brand_id,omitempty"`
	Size             string  `json:"size,omitempty"`
	GeminiAgreed     bool    `json:"gemini_agreed"`
	Confidence       float64 `json:"confidence"`
	Reason           string  `json:"reason,omitempty"`
	CacheHit         bool    `json:"cache_hit"`
	PhotoURL         string  `json:"photo_url"`
	ReferenceImage   string  `json:"reference_image_url,omitempty"`
	VerifiedViaImage bool    `json:"verified_via_image"`
	// v1.0.244 — face = "front" or "back"; extracted_mrp populated on back face.
	Face         string  `json:"face,omitempty"`
	ExtractedMRP float64 `json:"extracted_mrp,omitempty"`
	// v1.0.344 — combined photo-onboarding flow (batch_id set). AutoApplied =
	// the confident name/MRP was applied to the product immediately; Queued =
	// a low-confidence read was filed as a pending change for review. The
	// mobile capture screen shows "applied" vs a Use/Keep suggestion off these.
	AutoApplied bool `json:"auto_applied,omitempty"`
	Queued      bool `json:"queued,omitempty"`
	// change_request_id lets the mobile Use/Keep buttons approve/reject the
	// queued proposal for this product directly.
	ChangeRequestID string `json:"change_request_id,omitempty"`
	// v1.0.351 — set when a confident name read was NOT auto-applied because it
	// matches a DIFFERENT product that already exists at this shop+size (wrong
	// image / would-be duplicate). The change is queued for review instead.
	RenameBlockedReason string `json:"rename_blocked_reason,omitempty"`
}

// VerifyRow handles POST /stocks/smart-setup/verify-row.
func (h *SmartStockSetupVerifyHandler) VerifyRow(c *gin.Context) {
	if h.verifier == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "brand verifier not configured"})
		return
	}

	tenantIDStr, _ := c.Get("tenant_id")
	tenantID, err := uuid.Parse(fmt.Sprintf("%v", tenantIDStr))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found"})
		return
	}

	if err := c.Request.ParseMultipartForm(8 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to parse multipart: " + err.Error()})
		return
	}

	rowID := strings.TrimSpace(c.PostForm("row_id"))
	ocrText := strings.TrimSpace(c.PostForm("ocr_brand_text"))
	ocrSize := strings.TrimSpace(c.PostForm("ocr_size"))
	shopIDStr := strings.TrimSpace(c.PostForm("shop_id"))
	jobIDStr := strings.TrimSpace(c.PostForm("job_id"))
	// v1.0.244 — face is "front" (default) or "back". Back-face calls also
	// extract the M.R.P. printed on the back label.
	face := strings.ToLower(strings.TrimSpace(c.PostForm("face")))
	if face != "back" {
		face = "front"
	}
	// v1.0.252 — durable photo↔row binding. session_id is the Stock Setup
	// extraction session (varchar, same value stored on stock_setup_records);
	// row_number/page_number are the physical register position. Together
	// (tenant_id, session_id, page_number, row_number, face) is an EXACT key
	// the record build can backfill from, independent of whether the volatile
	// submit payload carried the URL. Stored raw (no uuid cast — the old
	// job_id::uuid cast is exactly why session never persisted before).
	sessionID := strings.TrimSpace(c.PostForm("session_id"))
	rowNumber := 0
	if v := strings.TrimSpace(c.PostForm("row_number")); v != "" {
		if n, perr := strconv.Atoi(v); perr == nil {
			rowNumber = n
		}
	}
	pageNumber := 0
	if v := strings.TrimSpace(c.PostForm("page_number")); v != "" {
		if n, perr := strconv.Atoi(v); perr == nil {
			pageNumber = n
		}
	}

	if rowID == "" || ocrText == "" || shopIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "row_id, ocr_brand_text, shop_id are required"})
		return
	}
	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id must be a UUID"})
		return
	}
	var jobID uuid.UUID
	if jobIDStr != "" {
		if parsed, err := uuid.Parse(jobIDStr); err == nil {
			jobID = parsed
		}
	}

	// Pull image from any of the standard field names.
	form := c.Request.MultipartForm
	var fileBytes []byte
	var contentType string
	for _, field := range []string{"photo", "file", "image"} {
		files := form.File[field]
		if len(files) == 0 {
			continue
		}
		fh := files[0]
		if fh.Size > 8*1024*1024 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Photo too large (max 8MB)"})
			return
		}
		f, ferr := fh.Open()
		if ferr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to open photo"})
			return
		}
		fileBytes, err = io.ReadAll(f)
		f.Close()
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read photo data"})
			return
		}
		contentType = strings.ToLower(fh.Header.Get("Content-Type"))
		break
	}
	if len(fileBytes) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no photo uploaded (use field 'photo', 'file', or 'image')"})
		return
	}
	if contentType == "" {
		contentType = "image/jpeg"
	}
	// v1.0.350 — same normalization as VerifyProduct, for parity.
	fileBytes, contentType = normalizeLabelImage(fileBytes, contentType)

	// Persist photo so Flutter can render the thumbnail + audit can prove it.
	// v1.0.244 — face suffix lets front + back coexist for the same row_id.
	photoURL := saveStockSetupVerifyPhoto(tenantID.String(), shopID.String(), rowID, face, fileBytes, contentType, h.logger)

	var (
		result   *services.BrandVerificationResult
		cacheHit bool
	)

	// v1.0.358 — tenant-wide image-hash cache FIRST (deterministic, shop-independent).
	// Both faces are safe here because the key is the IMAGE bytes: a different bottle
	// photo (different batch/year/MRP) hashes differently, so back-face MRP can't go
	// stale the way the old canonical-keyed cache could.
	imgSHA := ""
	if services.ImageVerifyHashEnabled() {
		imgSHA = services.ImageSHA256(fileBytes)
	}
	if imgSHA != "" {
		if cached := h.verifier.LookupImageHash(tenantID, imgSHA, face); cached != nil {
			result = cached
			cacheHit = true
		}
	}

	// Pre-fetch candidates (only needed when not an image-hash hit).
	var candidates []services.MasterBrandCandidate
	if result == nil {
		candidates = h.verifier.CandidatesForOCR(ocrText, 8)
	}

	// Cache lookup — v1.0.244: only short-circuit for FRONT face. The back
	// face must always go through Gemini because the M.R.P. value depends on
	// the specific bottle photographed (different batches / years can print
	// different MRPs even for the same canonical brand) — caching back would
	// risk returning a stale MRP.
	if result == nil && face == "front" {
		// Cache #1 — saas_brands.picture exact-canonical match.
		if cached := h.verifier.LookupCachedCanonical(ocrText, candidates); cached != nil {
			cacheHit = true
			result = &services.BrandVerificationResult{
				CanonicalName: cached.Name,
				MasterBrandID: cached.ID,
				Size:          ocrSize,
				GeminiAgreed:  true,
				Confidence:    1.0,
				Reason:        "cache_hit_exact_canonical",
				CacheHit:      true,
				Face:          face,
			}
		} else if aliasCached := h.lookupAliasCache(c, tenantID, shopID, ocrText); aliasCached != nil {
			// Cache #2 — alias fast-path (image_verify alias already exists +
			// resolved master has a reference image). Free repeat verifications.
			cacheHit = true
			aliasCached.Face = face
			result = aliasCached
		}
	}

	// No cache hit (or back face) → call Gemini.
	if result == nil {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 35*time.Second)
		defer cancel()
		var err error
		result, err = h.verifier.Verify(ctx, fileBytes, contentType, ocrText, ocrSize, candidates, face)
		if err != nil {
			h.logger.WithError(err).WithFields(logrus.Fields{
				"tenant": tenantID, "shop": shopID, "ocr": ocrText, "face": face,
			}).Warn("VerifyRow: Gemini call failed")
			// Fail-safe: row stays unverified, operator can retry.
			c.JSON(http.StatusBadGateway, gin.H{
				"error":     "verification failed: " + err.Error(),
				"photo_url": photoURL,
			})
			return
		}
	}

	// v1.0.358 — store a confident FRESH read so later uploads of this exact image
	// are deterministic across shops (store-only-confident; skip cache hits).
	if imgSHA != "" && !cacheHit && result != nil && result.Confidence >= 0.5 {
		h.verifier.StoreImageHash(tenantID, imgSHA, face, result)
	}

	// Side effects: populate cache + write alias + audit row.
	if result.MasterBrandID != "" {
		_ = h.verifier.PopulatePictureIfMissing(result.MasterBrandID, photoURL)
	}

	// Learn alias: raw OCR text → canonical brand (shop+tenant scope).
	// LearnAliasScoped guards against hygiene-blocked aliases internally.
	//
	// v1.0.257 — ANTI-POISON guard. Previously ANY non-empty Gemini canonical
	// was learned as a shop+tenant routing alias, even when the read did not
	// resolve to a real master brand. That minted the bogus
	// "8 pm special rare whisky → 8 PM GOLD" alias ("8 PM GOLD" is not a
	// product) on chhotu's shop AND tenant-wide, which then silently
	// re-routed genuine 8 PM rows. An UNANCHORED (no MasterBrandID) or
	// low-confidence read must never become a routing rule — only confident,
	// catalog-anchored verifications are allowed to teach the matcher.
	aliasAnchored := result.MasterBrandID != "" && result.Confidence >= 0.5
	if result.CanonicalName != "" && ocrText != "" && h.alias != nil && aliasAnchored {
		if err := h.alias.LearnAliasScoped(tenantID, shopID, ocrText, result.CanonicalName, nil, "image_verify"); err != nil {
			h.logger.WithError(err).Debug("VerifyRow: LearnAliasScoped (shop) skipped")
		}
		// Also learn at tenant scope so other shops in the same tenant benefit later.
		_ = h.alias.LearnAliasScoped(tenantID, uuid.Nil, ocrText, result.CanonicalName, nil, "image_verify_tenant")
	} else if result.CanonicalName != "" && ocrText != "" {
		h.logger.WithFields(logrus.Fields{
			"ocr": ocrText, "canonical": result.CanonicalName,
			"master_brand_id": result.MasterBrandID, "confidence": result.Confidence,
		}).Info("VerifyRow: alias NOT learned — unanchored/low-confidence read (anti-poison guard v1.0.257)")
	}

	// Audit row — always write, even on cache hit, so cost telemetry is complete.
	// v1.0.244 — face + extracted_mrp captured.
	if err := h.db.DB.Exec(`
		INSERT INTO stock_setup_image_verifications
		  (tenant_id, shop_id, job_id, ocr_brand_text, ocr_size, image_url,
		   matched_brand_id, canonical_name, gemini_agreed, confidence, cache_hit,
		   face, extracted_mrp, session_id, row_number, page_number, row_id)
		VALUES (?, ?, NULLIF(?, '00000000-0000-0000-0000-000000000000'::uuid),
		        ?, ?, ?, NULLIF(?, '')::uuid, ?, ?, ?, ?, ?, NULLIF(?, 0),
		        NULLIF(?, ''), NULLIF(?, 0), NULLIF(?, 0), NULLIF(?, ''))
	`, tenantID, shopID, jobID, ocrText, ocrSize, photoURL,
		result.MasterBrandID, result.CanonicalName,
		result.GeminiAgreed, result.Confidence, cacheHit,
		face, result.ExtractedMRP,
		sessionID, rowNumber, pageNumber, rowID,
	).Error; err != nil {
		h.logger.WithError(err).Warn("VerifyRow: audit insert failed (non-fatal)")
	}

	// v1.0.243 — Only mark VerifiedViaImage=true when Gemini gave a usable
	// reading. confidence=0 means "no liquor in photo" / "unreadable" — the
	// row must stay unverified so the operator retakes the photo. Cache hits
	// always count as verified (confidence=1.0 by construction).
	verified := cacheHit || result.Confidence >= 0.5

	c.JSON(http.StatusOK, verifyRowResponse{
		RowID:            rowID,
		CanonicalName:    result.CanonicalName,
		MasterBrandID:    result.MasterBrandID,
		Size:             result.Size,
		GeminiAgreed:     result.GeminiAgreed,
		Confidence:       result.Confidence,
		Reason:           result.Reason,
		CacheHit:         cacheHit,
		PhotoURL:         photoURL,
		VerifiedViaImage: verified,
		Face:             face,
		ExtractedMRP:     result.ExtractedMRP,
	})
}

// lookupAliasCache checks ocr_brand_aliases for a prior image_verify entry
// matching the operator's OCR text. If the resolved canonical brand has a
// reference image in saas_brands.picture, we accept it as a verified hit
// without calling Gemini. Returns nil on miss.
func (h *SmartStockSetupVerifyHandler) lookupAliasCache(
	c *gin.Context,
	tenantID uuid.UUID,
	shopID uuid.UUID,
	ocrText string,
) *services.BrandVerificationResult {
	if h.alias == nil || h.db == nil {
		return nil
	}
	// Use the existing alias cascade (shop → tenant exact → fuzzy) but only
	// trust matches that previously came from image_verify (high signal).
	var row struct {
		CanonicalName string
		Source        string
	}
	// Normalise both sides: lowercase + strip everything non-alphanumeric + collapse spaces.
	// Matches the same normaliseString() the verifier uses on canonical names.
	err := h.db.DB.Raw(`
		SELECT canonical_brand_name AS canonical_name, source
		FROM ocr_brand_aliases
		WHERE tenant_id = ?
		  AND deleted_at IS NULL
		  AND source IN ('image_verify', 'image_verify_tenant')
		  AND regexp_replace(regexp_replace(LOWER(alias_name), '[^a-z0-9]+', ' ', 'g'), '\s+', ' ', 'g')
		      = regexp_replace(regexp_replace(LOWER(?), '[^a-z0-9]+', ' ', 'g'), '\s+', ' ', 'g')
		  AND (shop_id = ? OR shop_id IS NULL)
		ORDER BY (shop_id = ?) DESC, last_used_at DESC NULLS LAST
		LIMIT 1
	`, tenantID, ocrText, shopID, shopID).Scan(&row).Error
	if err != nil || row.CanonicalName == "" {
		return nil
	}
	// Resolve back to master_brand_id + confirm there's a reference picture.
	var brand struct {
		ID      string
		Name    string
		Picture string
	}
	if dbErr := h.db.DB.Raw(`
		SELECT id, name, COALESCE(picture, '') AS picture
		FROM saas_brands
		WHERE deleted_at IS NULL
		  AND regexp_replace(regexp_replace(LOWER(name), '[^a-z0-9]+', ' ', 'g'), '\s+', ' ', 'g')
		      = regexp_replace(regexp_replace(LOWER(?), '[^a-z0-9]+', ' ', 'g'), '\s+', ' ', 'g')
		LIMIT 1
	`, row.CanonicalName).Scan(&brand).Error; dbErr != nil || brand.ID == "" || brand.Picture == "" {
		return nil
	}
	return &services.BrandVerificationResult{
		CanonicalName: brand.Name,
		MasterBrandID: brand.ID,
		Size:          c.PostForm("ocr_size"),
		GeminiAgreed:  true,
		Confidence:    1.0,
		Reason:        "cache_hit_alias",
		CacheHit:      true,
	}
}

// saveStockSetupVerifyPhoto stores the bytes under a stable path so Flutter
// can fetch a thumbnail later. Returns the relative URL on success, "" on
// any failure (the verify response still succeeds — photo is best-effort).
func saveStockSetupVerifyPhoto(tenant, shop, rowID, face string, data []byte, contentType string, logger *logrus.Logger) string {
	if face == "" {
		face = "front"
	}
	dir := filepath.Join("/app/uploads/stock_setup/verifications", tenant, shop)
	if err := mkdirAllBestEffort(dir); err != nil {
		if logger != nil {
			logger.WithError(err).Warnf("saveStockSetupVerifyPhoto: mkdir %s failed", dir)
		}
		return ""
	}
	ext := ".jpg"
	if strings.Contains(contentType, "png") {
		ext = ".png"
	} else if strings.Contains(contentType, "webp") {
		ext = ".webp"
	}
	// v1.0.244 — embed face in filename so front + back coexist for the same rowID.
	fname := rowID + "-" + face + "-" + strconv.FormatInt(time.Now().UnixMilli(), 10) + ext
	path := filepath.Join(dir, fname)
	if err := writeFileBestEffort(path, data); err != nil {
		if logger != nil {
			logger.WithError(err).Warnf("saveStockSetupVerifyPhoto: write %s failed", path)
		}
		return ""
	}
	// Return public URL — uploads/ is mounted by nginx as /uploads.
	return "/uploads/stock_setup/verifications/" + tenant + "/" + shop + "/" + fname
}

// saveProductVerifyPhoto stores the bytes under /app/uploads/products/.
// Mirrors saveStockSetupVerifyPhoto but keyed on productID so the path is
// stable across re-uploads for the same product.
//
// v1.0.250 — used by the standalone inventory-page photo upload flow so an
// operator can verify any product (existing or newly created) outside of
// the Stock Setup screen.
func saveProductVerifyPhoto(tenant, shop, productID, face string, data []byte, contentType string, logger *logrus.Logger) string {
	if face == "" {
		face = "front"
	}
	dir := filepath.Join("/app/uploads/products", tenant, shop)
	if err := mkdirAllBestEffort(dir); err != nil {
		if logger != nil {
			logger.WithError(err).Warnf("saveProductVerifyPhoto: mkdir %s failed", dir)
		}
		return ""
	}
	ext := ".jpg"
	if strings.Contains(contentType, "png") {
		ext = ".png"
	} else if strings.Contains(contentType, "webp") {
		ext = ".webp"
	}
	fname := productID + "-" + face + "-" + strconv.FormatInt(time.Now().UnixMilli(), 10) + ext
	path := filepath.Join(dir, fname)
	if err := writeFileBestEffort(path, data); err != nil {
		if logger != nil {
			logger.WithError(err).Warnf("saveProductVerifyPhoto: write %s failed", path)
		}
		return ""
	}
	return "/uploads/products/" + tenant + "/" + shop + "/" + fname
}

// productImgNormalizeEnabled gates v1.0.350 label-image normalization. Default
// ON; set PRODUCT_IMG_NORMALIZE=0 to store the original bytes unchanged.
func productImgNormalizeEnabled() bool {
	return os.Getenv("PRODUCT_IMG_NORMALIZE") != "0"
}

// maxLabelEdge caps the longest edge of a stored product-label photo.
const maxLabelEdge = 1600

// normalizeLabelImage decode-validates a captured product-label photo and, when
// it decodes, downscales the longest edge to <= maxLabelEdge and re-encodes JPEG
// Q80 — so every capture path (the Flutter screens each used a different client
// quality) lands a consistent image safely under the 8MB cap regardless of the
// client. On ANY decode/encode failure it returns the ORIGINAL bytes + content
// type untouched: this never rejects a capture (webp/exotic inputs and the
// "trust the photo" gate at VerifyProduct must keep working — normalization is a
// best-effort safety net, not a validator).
func normalizeLabelImage(raw []byte, contentType string) ([]byte, string) {
	if !productImgNormalizeEnabled() || len(raw) == 0 {
		return raw, contentType
	}
	img, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return raw, contentType // store raw; never hard-fail a capture
	}
	b := img.Bounds()
	w, hgt := b.Dx(), b.Dy()
	if w == 0 || hgt == 0 {
		return raw, contentType
	}
	longest := w
	if hgt > w {
		longest = hgt
	}
	// Only re-encode when it actually helps — oversized edge or heavy bytes.
	if longest <= maxLabelEdge && len(raw) <= 1500*1024 {
		return raw, contentType
	}
	dstW, dstH := w, hgt
	if longest > maxLabelEdge {
		scale := float64(maxLabelEdge) / float64(longest)
		dstW = int(float64(w) * scale)
		dstH = int(float64(hgt) * scale)
	}
	dst := image.NewRGBA(image.Rect(0, 0, dstW, dstH))
	draw.CatmullRom.Scale(dst, dst.Bounds(), img, b, draw.Over, nil)
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, dst, &jpeg.Options{Quality: 80}); err != nil {
		return raw, contentType
	}
	return buf.Bytes(), "image/jpeg"
}

// VerifyProduct handles POST /products/:id/verify-photo.
//
// v1.0.250 — Per-product Front/Back photo verification, used by:
//   1. Inventory product edit screen — operator photographs a brand they
//      already have in stock; brand name + MRP corrections offered.
//   2. Manual Purchase product picker — operator adds photos to a product
//      they're about to receive stock for.
//   3. Stock Setup "Add Missing Brands" manual entries — same chip widget,
//      now with a real upload endpoint backing it.
//
// Form fields:
//   - photo (multipart file, required)
//   - face: "front" | "back" (default "front")
//   - shop_id (uuid)
//   - ocr_text: optional — operator-typed text. Falls back to product.Name.
//   - ocr_size: optional — falls back to product.Size.
//
// On success: persists URL + verified flag + back_image_mrp onto products row,
// returns canonical_name + confidence + extracted_mrp so Flutter can offer
// brand-name and MRP corrections.
func (h *SmartStockSetupVerifyHandler) VerifyProduct(c *gin.Context) {
	if h.verifier == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "brand verifier not configured"})
		return
	}

	tenantIDStr, _ := c.Get("tenant_id")
	tenantID, err := uuid.Parse(fmt.Sprintf("%v", tenantIDStr))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found"})
		return
	}

	productIDStr := c.Param("id")
	productID, err := uuid.Parse(productIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid product id"})
		return
	}

	shopIDStr := strings.TrimSpace(c.PostForm("shop_id"))
	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	face := strings.ToLower(strings.TrimSpace(c.PostForm("face")))
	if face != "back" {
		face = "front"
	}

	// Pull the product so we can fall back to its name/size when the caller
	// didn't pass an ocr_text override. Also verifies the product belongs to
	// this tenant (defence-in-depth — middleware should already do this).
	var prod struct {
		Name string
		Size string
		MRP  float64
	}
	if dbErr := h.db.DB.Table("products").
		Select("name, size, mrp").
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", productID, tenantID).
		Scan(&prod).Error; dbErr != nil || prod.Name == "" {
		c.JSON(http.StatusNotFound, gin.H{"error": "product not found"})
		return
	}

	// v1.0.344 — combined-request context. batch_id is sent ONLY by the
	// AI-Purchase photo-onboarding flow; it groups every product captured in one
	// session into a single reviewable request on the web admin portal. When
	// absent, behaviour is byte-for-byte the legacy immediate-photo path, so the
	// inventory-edit / manual-purchase callers are unaffected.
	batchID, _ := uuid.Parse(strings.TrimSpace(c.PostForm("batch_id")))
	inBatch := batchID != uuid.Nil
	var requestedBy uuid.UUID
	if uid, ok := c.Get("user_id"); ok {
		requestedBy, _ = uuid.Parse(fmt.Sprintf("%v", uid))
	}
	var requestedByName string
	if requestedBy != uuid.Nil {
		var u struct {
			First string `gorm:"column:first_name"`
			Last  string `gorm:"column:last_name"`
		}
		h.db.DB.Table("users").Select("first_name, last_name").
			Where("id = ? AND tenant_id = ?", requestedBy, tenantID).Scan(&u)
		requestedByName = strings.TrimSpace(strings.TrimSpace(u.First) + " " + strings.TrimSpace(u.Last))
	}

	ocrText := strings.TrimSpace(c.PostForm("ocr_text"))
	if ocrText == "" {
		ocrText = prod.Name
	}
	ocrSize := strings.TrimSpace(c.PostForm("ocr_size"))
	if ocrSize == "" {
		ocrSize = prod.Size
	}

	// Read multipart photo. Same flexible field-name handling as VerifyRow.
	var fileBytes []byte
	var contentType string
	for _, field := range []string{"photo", "file", "image"} {
		if fh, errF := c.FormFile(field); errF == nil && fh != nil {
			openF, oErr := fh.Open()
			if oErr != nil {
				continue
			}
			defer openF.Close()
			fileBytes, _ = io.ReadAll(openF)
			contentType = fh.Header.Get("Content-Type")
			break
		}
	}
	if len(fileBytes) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "photo file is required (field: photo, file, or image)"})
		return
	}
	if len(fileBytes) > 8*1024*1024 {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "photo exceeds 8MB"})
		return
	}
	if contentType == "" {
		contentType = "image/jpeg"
	}
	// v1.0.350 — one consistent stored image regardless of which screen/quality
	// the client captured at (best-effort; raw on decode failure).
	fileBytes, contentType = normalizeLabelImage(fileBytes, contentType)

	photoURL := saveProductVerifyPhoto(tenantID.String(), shopID.String(), productID.String(), face, fileBytes, contentType, h.logger)

	// v1.0.358 — tenant-wide image-hash cache (deterministic, shop-independent):
	// the SAME bottle photo returns the SAME name/MRP at every shop in the tenant.
	// On a hit we skip Gemini + the per-shop candidate work entirely (which is what
	// caused the same image to read differently per shop). Fail-open on any error.
	imgSHA := ""
	if services.ImageVerifyHashEnabled() {
		imgSHA = services.ImageSHA256(fileBytes)
	}
	var result *services.BrandVerificationResult
	var vErr error
	if imgSHA != "" {
		result = h.verifier.LookupImageHash(tenantID, imgSHA, face)
	}
	if result == nil {
		candidates := h.verifier.CandidatesForOCR(ocrText, 8)
		ctx, cancel := context.WithTimeout(c.Request.Context(), 35*time.Second)
		defer cancel()
		result, vErr = h.verifier.Verify(ctx, fileBytes, contentType, ocrText, ocrSize, candidates, face)
	}
	if vErr != nil {
		// v1.0.338 — TRUST THE PHOTO even when verification is unavailable. The
		// front/back gate only needs a photo ON FILE; Gemini name/MRP extraction
		// is a bonus. Previously a Gemini timeout returned 502 WITHOUT writing
		// front_image_url/back_image_url, so under the strict front+back purchase
		// gate the operator captured a valid photo, got an error, and the product
		// STAYED blocked — a hard stall across a ~250-photo session. Persist the
		// saved photo onto the correct face and report success so the capture
		// flow advances; the name/MRP verification is simply skipped this time.
		h.logger.WithError(vErr).Warn("VerifyProduct: Gemini call failed — persisting photo anyway so the strict front+back gate clears")
		faceCol := "front_image_url"
		if face == "back" {
			faceCol = "back_image_url"
		}
		if photoURL != "" {
			if uErr := h.db.DB.Table("products").
				Where("id = ? AND tenant_id = ?", productID, tenantID).
				Updates(map[string]interface{}{faceCol: photoURL, "photo_verified_at": time.Now()}).Error; uErr != nil {
				h.logger.WithError(uErr).Warnf("VerifyProduct: failed to persist photo URL on product %s after Gemini failure", productID)
			}
		}
		c.JSON(http.StatusOK, verifyRowResponse{
			RowID:            productID.String(),
			PhotoURL:         photoURL,
			VerifiedViaImage: false,
			Face:             face,
			Reason:           "photo saved; name/price check skipped (service busy)",
		})
		return
	}

	// v1.0.358 — cache a confident FRESH read (not a cache hit) so later uploads of
	// this exact image are deterministic across shops. Store-only-confident so a
	// noise read can never poison the tenant-wide answer.
	if imgSHA != "" && !result.CacheHit && result.Confidence >= 0.5 {
		h.verifier.StoreImageHash(tenantID, imgSHA, face, result)
	}

	verified := result.Confidence >= 0.5
	const nameRewriteConfidence = 0.6
	confident := result.Confidence >= nameRewriteConfidence

	// Persist onto products row so the photo appears everywhere this product is shown.
	productUpdates := map[string]interface{}{
		"photo_verified_at": time.Now(),
	}
	mrpRewritten := false
	if face == "front" {
		productUpdates["front_image_url"] = photoURL
		if verified {
			productUpdates["verified_via_image_front"] = true
		}
	} else {
		productUpdates["back_image_url"] = photoURL
		if verified {
			productUpdates["verified_via_image_back"] = true
		}
		if result.ExtractedMRP > 0 {
			productUpdates["back_image_mrp"] = result.ExtractedMRP
		}
		// v1.0.344 — in the photo-onboarding batch flow, a CONFIDENT back-label
		// MRP read is auto-applied to the product ("auto-apply confident, queue
		// the rest"); a low-confidence read is queued for approval below.
		// Non-batch callers keep the legacy behaviour (back_image_mrp suggestion
		// only — the product MRP is never silently changed from a photo).
		if inBatch && confident && result.ExtractedMRP > 0 && result.ExtractedMRP != prod.MRP {
			productUpdates["mrp"] = result.ExtractedMRP
			productUpdates["last_mrp_change_at"] = time.Now()
			productUpdates["last_mrp_change_previous"] = prod.MRP
			if requestedBy != uuid.Nil {
				productUpdates["last_mrp_change_by_id"] = requestedBy
				productUpdates["last_mrp_change_by_name"] = requestedByName
			}
			mrpRewritten = true
		}
	}
	// 2026-05-17 — TRUST THE IMAGE. "Images can't lie." When the bottle
	// photo is read confidently, this is the authoritative name fix for an
	// unverified product (raw Stock-Setup text like "100 Step"): overwrite
	// name + display_name, mark name_verified=true so the purchase gate
	// opens, and learn an alias so the SAME garbled OCR text auto-resolves
	// to the correct product on every future Stock Setup / Smart Purchase.
	canonical := strings.TrimSpace(result.CanonicalName)
	nameRewritten := false
	renameBlocked := false
	var renameBlockReason string
	// v1.0.389 — empty strays that collided with the proposed identity but are
	// unused clutter (0 stock, no photo, never sold); consolidated after a
	// successful rename so they can't keep blocking it.
	var renameConsolidate []uuid.UUID
	if verified {
		wantsRename := canonical != "" && confident &&
			!strings.EqualFold(canonical, strings.TrimSpace(prod.Name))

		// v1.0.351 — WRONG-IMAGE / DUPLICATE GUARD. A confident read is normally
		// trusted ("images can't lie"), but it must NOT silently rename THIS
		// product into the identity of a DIFFERENT product that already exists at
		// this shop+size (e.g. garbled "imjum" → existing "M2 Magic Moments
		// Superior Vodka 180ml"). That mints a duplicate and buries this product's
		// stock under the wrong name. On collision we apply nothing and queue the
		// proposal for human review instead.
		if wantsRename {
			dup, why, strays := services.PhotoRenameWouldDuplicate(
				h.db.DB, tenantID, shopID, productID, prod.Size, result.MasterBrandID, canonical)
			if dup {
				renameBlocked = true
				renameBlockReason = why
				h.logger.Warnf("VerifyProduct: photo rename of %s %q → %q BLOCKED from auto-apply — %s (queued for review)",
					productID, strings.TrimSpace(prod.Name), canonical, why)
			} else {
				// v1.0.389 — empty unused strays that collided with the proposed
				// identity but are clutter (0 stock, no photo, never sold). Don't
				// block the rename; consolidate them after it applies.
				renameConsolidate = strays
			}
		}

		// name_verified opens the purchase gate by vouching the product's identity.
		// v1.0.355 — require an actually CONFIDENT read (was `!inBatch || confident`,
		// which vouched ANY non-batch verify regardless of confidence and so blessed
		// wrong names from blurry/ambiguous photos). The legitimate "operator confirms
		// the existing name with a clear photo" case is itself confident, so it still
		// vouches; only low-confidence reads stop vouching. `verified` (>=0.5) still
		// persisted the photo + front/back gate flags above, so the purchase photo-gate
		// behaviour is unchanged.
		if confident && !renameBlocked {
			productUpdates["name_verified"] = true
		}
		if wantsRename && !renameBlocked {
			productUpdates["name"] = canonical
			productUpdates["display_name"] = canonical
			// Stale bold range would mis-highlight the new name; clear it.
			productUpdates["display_name_bold_start"] = nil
			productUpdates["display_name_bold_length"] = nil
			nameRewritten = true

			// v1.0.355 — KEEP IDENTITY IN SYNC WITH THE NAME. Renaming name/display_name
			// while leaving brand_id (tenant brand, shown as the product-detail popup's
			// second line) and saas_brand_id (excise/catalog identity) pointing at the
			// OLD product is exactly the drift the owner reported ("O.P.N Green Label"
			// still linked to "Officer's Choice Blue Reserve"). Re-point them so the
			// display name and the excise name always describe the SAME product.
			// Gated by PHOTO_RENAME_SYNC_BRAND (default-on).
			if os.Getenv("PHOTO_RENAME_SYNC_BRAND") != "0" {
				// saas_brand_id: set to the read's resolved master when present; else
				// CLEAR it (NULL = honestly uncatalogued) rather than leave a wrong
				// link. Always clear saas_variant_id (a stale variant of the OLD brand
				// would contradict the new identity; unique index excludes NULLs so
				// clearing is collision-safe; next Stock-Setup re-links by brand+size).
				if mid, perr := uuid.Parse(strings.TrimSpace(result.MasterBrandID)); perr == nil && mid != uuid.Nil {
					productUpdates["saas_brand_id"] = mid
				} else {
					productUpdates["saas_brand_id"] = nil
				}
				productUpdates["saas_variant_id"] = nil
				// tenant brand_id: re-resolve from the new name (reuses the 70%-fuzzy
				// find-or-create), so the popup's brand line follows the rename. Best
				// effort — a failure must not fail the capture.
				if h.setupSvc != nil {
					if bid, bErr := h.setupSvc.ResolveOrCreateBrandID(h.db.DB, tenantID, canonical); bErr == nil && bid != uuid.Nil {
						productUpdates["brand_id"] = bid
					} else if bErr != nil {
						h.logger.WithError(bErr).Warnf("VerifyProduct: brand_id re-resolve skipped for %q", canonical)
					}
				}
			}
		}
	}

	if upErr := h.db.DB.Table("products").
		Where("id = ? AND tenant_id = ?", productID, tenantID).
		Updates(productUpdates).Error; upErr != nil {
		h.logger.WithError(upErr).Warnf("VerifyProduct: failed to persist photo on product %s", productID)
	} else if nameRewritten {
		// v1.0.389 — the rename took THIS (real, photographed) product to an
		// identity that one or more EMPTY STRAYS were squatting on. Soft-delete
		// those strays so they can't keep blocking future image-renames (the
		// Rockford "Reserve Premium" loop) and don't show as duplicates.
		now := time.Now()
		for _, sid := range renameConsolidate {
			if sid == uuid.Nil || sid == productID {
				continue
			}
			h.db.DB.Table("products").Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", sid, tenantID).
				Updates(map[string]interface{}{"deleted_at": now, "updated_at": now})
			h.db.DB.Table("stocks").Where("product_id = ? AND deleted_at IS NULL", sid).
				Updates(map[string]interface{}{"deleted_at": now, "updated_at": now})
			h.logger.Infof("VerifyProduct: consolidated empty stray %s into renamed product %s (%q)", sid, productID, canonical)
		}
		if h.alias != nil {
		// Teach both the operator-typed/raw text and the old product name so
		// the next extraction of either resolves straight to this product.
		oldName := strings.TrimSpace(prod.Name)
		for _, key := range []string{strings.TrimSpace(ocrText), oldName} {
			if key == "" || strings.EqualFold(key, canonical) {
				continue
			}
			if aErr := h.alias.LearnAliasScoped(tenantID, shopID, key, canonical, &productID, "inventory_photo_verify"); aErr != nil {
				h.logger.WithError(aErr).Debugf("VerifyProduct: alias learn skipped for %q→%q", key, canonical)
			}
		}
		h.logger.Infof("VerifyProduct: name_verified product %s '%s' → '%s' (conf %.2f) from trusted photo", productID, oldName, canonical, result.Confidence)
		}
	}

	resp := verifyRowResponse{
		RowID:            productID.String(),
		CanonicalName:    result.CanonicalName,
		MasterBrandID:    result.MasterBrandID,
		Size:             result.Size,
		GeminiAgreed:     result.GeminiAgreed,
		Confidence:       result.Confidence,
		Reason:           result.Reason,
		CacheHit:         result.CacheHit,
		PhotoURL:         photoURL,
		VerifiedViaImage: verified,
		Face:             face,
		ExtractedMRP:     result.ExtractedMRP,
	}
	if renameBlocked {
		resp.RenameBlockedReason = renameBlockReason
	}

	// v1.0.344 — record this face into the combined photo change-request so it
	// surfaces as one request on the web admin portal (and the mobile review).
	// Best-effort: a failure here must not fail the capture — the photo gate has
	// already cleared (front/back URL persisted above).
	if inBatch {
		in := services.PhotoChangeInput{
			TenantID:        tenantID,
			ShopID:          &shopID,
			ProductID:       productID,
			BatchID:         batchID,
			Face:            face,
			CurrentName:     strings.TrimSpace(prod.Name),
			ProposedName:    canonical,
			CurrentMRP:      prod.MRP,
			ProposedMRP:     result.ExtractedMRP,
			Confidence:      result.Confidence,
			PhotoURL:        photoURL,
			RequestedByID:   requestedBy,
			RequestedByName: requestedByName,
		}
		if face == "front" {
			in.Applied = nameRewritten
		} else {
			in.Applied = mrpRewritten
		}
		if crID, recErr := services.RecordPhotoChangeRequest(h.db.DB, in); recErr != nil {
			h.logger.WithError(recErr).Warnf("VerifyProduct: failed to record combined change-request for product %s", productID)
		} else if crID != uuid.Nil {
			resp.ChangeRequestID = crID.String()
		}
		// Tell the app whether this face was applied immediately or queued.
		if face == "front" {
			resp.AutoApplied = nameRewritten
			resp.Queued = canonical != "" && !nameRewritten && !strings.EqualFold(canonical, strings.TrimSpace(prod.Name))
		} else {
			resp.AutoApplied = mrpRewritten
			resp.Queued = result.ExtractedMRP > 0 && !mrpRewritten && result.ExtractedMRP != prod.MRP
		}
	}

	c.JSON(http.StatusOK, resp)
}

// ProductPhotoStatus handles GET /products/photo-status?shop_id=.
//
// v1.0.344 — powers the AI-Purchase precondition. Returns, for one shop, the
// FORWARD-ONLY products (created_via in stock_setup / ai_purchase) that still
// need a front and/or back photo before the home Purchase Entry button unlocks.
// Legacy products (created_via='legacy_exempt' etc.) are intentionally excluded
// so the first onboarding only demands photos for AI-created SKUs. Shop scope
// mirrors the inventory list exactly: products with a non-deleted stock row in
// the shop (product_service.go).
func (h *SmartStockSetupVerifyHandler) ProductPhotoStatus(c *gin.Context) {
	tenantIDStr, _ := c.Get("tenant_id")
	tenantID, err := uuid.Parse(fmt.Sprintf("%v", tenantIDStr))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found"})
		return
	}
	shopIDStr := strings.TrimSpace(c.Query("shop_id"))
	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	type prodRow struct {
		ID           uuid.UUID `gorm:"column:id"`
		Name         string    `gorm:"column:name"`
		Size         string    `gorm:"column:size"`
		Front        string    `gorm:"column:front_image_url"`
		Back         string    `gorm:"column:back_image_url"`
		NameVerified bool      `gorm:"column:name_verified"`
		MRP          float64   `gorm:"column:mrp"`
		CreatedVia   string    `gorm:"column:created_via"`
	}
	var rows []prodRow
	if dbErr := h.db.DB.Table("products").
		Select("id, name, size, front_image_url, back_image_url, name_verified, mrp, created_via").
		Where(`tenant_id = ? AND deleted_at IS NULL
		        AND created_via IN ('stock_setup','ai_purchase')
		        AND id IN (SELECT product_id FROM stocks WHERE shop_id = ? AND deleted_at IS NULL)`,
			tenantID, shopID).
		Order("name").
		Scan(&rows).Error; dbErr != nil {
		h.logger.WithError(dbErr).Error("ProductPhotoStatus: query failed")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load photo status"})
		return
	}

	// v1.0.356 — a product is "ready" for AI purchase only when it has BOTH photos
	// AND a verified name. Post-v355 name_verified=true means name+brand+excise are
	// consistent, so requiring it is the real 100%-verified bar (a clear photo sets
	// it automatically on a confident read). Kill-switch PURCHASE_REQUIRE_NAME_VERIFIED.
	requireNameVerified := os.Getenv("PURCHASE_REQUIRE_NAME_VERIFIED") != "0"
	// v1.0.357 — BACK image is OPTIONAL. Correct item consideration only needs the
	// FRONT (brand/name) + a verified name; the back just carries MRP, which the
	// operator can type. So a product with front+verified but no back is "ready"
	// and never blocks an AI purchase. Set PURCHASE_REQUIRE_BACK_IMAGE=1 to re-require it.
	requireBack := os.Getenv("PURCHASE_REQUIRE_BACK_IMAGE") == "1"

	type statusProduct struct {
		ProductID      string  `json:"product_id"`
		Name           string  `json:"name"`
		Size           string  `json:"size,omitempty"`
		FrontImage     string  `json:"front_image_url,omitempty"`
		BackImage      string  `json:"back_image_url,omitempty"`
		MissingFront   bool    `json:"missing_front"`
		MissingBack    bool    `json:"missing_back"`
		UnverifiedName bool    `json:"unverified_name"`
		NameVerified   bool    `json:"name_verified"`
		MRP            float64 `json:"mrp"`
		CreatedVia     string  `json:"created_via"`
	}
	incomplete := make([]statusProduct, 0)
	for _, r := range rows {
		missingFront := strings.TrimSpace(r.Front) == ""
		missingBack := strings.TrimSpace(r.Back) == ""
		blockingBack := requireBack && missingBack // back optional unless flag set
		unverifiedName := requireNameVerified && !r.NameVerified
		if !missingFront && !blockingBack && !unverifiedName {
			continue
		}
		incomplete = append(incomplete, statusProduct{
			ProductID:      r.ID.String(),
			Name:           r.Name,
			Size:           r.Size,
			FrontImage:     r.Front,
			BackImage:      r.Back,
			MissingFront:   missingFront,
			MissingBack:    missingBack,
			UnverifiedName: unverifiedName,
			NameVerified:   r.NameVerified,
			MRP:            r.MRP,
			CreatedVia:     r.CreatedVia,
		})
	}

	requiredTotal := len(rows)
	incompleteCount := len(incomplete)
	c.JSON(http.StatusOK, gin.H{
		"shop_id":        shopID.String(),
		"required_total": requiredTotal,
		"complete":       requiredTotal - incompleteCount,
		"incomplete":     incompleteCount,
		"is_complete":    incompleteCount == 0,
		"products":       incomplete,
	})
}

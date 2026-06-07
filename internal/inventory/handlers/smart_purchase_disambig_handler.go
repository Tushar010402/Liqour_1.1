package handlers

import (
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	"github.com/sirupsen/logrus"
)

// SmartPurchaseDisambigHandler exposes POST
// /api/inventory/purchases/smart-purchase/disambig.
//
// v1.0.222 — closes the Row-23 class problem: when v221 surfaces a tenant
// with 2+ products under the same (saas_brand_id, size_ml) but different
// flavour variants, the operator uploads a past-purchase bill that names
// the specific variant. We extract that bill, resolve the canonical brand
// (which includes the flavour suffix this time), pick the matching tenant
// product, and learn the alias so the next bill resolves silently.
//
// Multipart form:
//   image            (file)   the past-purchase image
//   gp_canonical     (string) the ambiguous GP-canonical brand text
//   size_ml          (int)    the size from the current GP row
//   shop_id          (uuid)   shop scope for alias learning
//   candidate_ids    (csv)    optional UUID list of the ambiguous tenant
//                             products (defensive — disambig refuses to
//                             return a product outside the set)
//
// Response: 200 OK with services.DisambigResult.
//           400 on bad request / 422 on no_match / 500 on extraction failure.
type SmartPurchaseDisambigHandler struct {
	service *services.SmartPurchaseService
	logger  *logrus.Logger
}

func NewSmartPurchaseDisambigHandler(service *services.SmartPurchaseService, logger *logrus.Logger) *SmartPurchaseDisambigHandler {
	return &SmartPurchaseDisambigHandler{service: service, logger: logger}
}

// Resolve handles POST /purchases/smart-purchase/disambig.
func (h *SmartPurchaseDisambigHandler) Resolve(c *gin.Context) {
	if h.service == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Purchase disambig not configured"})
		return
	}
	tenantID, terr := tenantUUIDFromContext(c)
	if terr != nil {
		c.JSON(terr.status, gin.H{"error": terr.msg})
		return
	}

	shopIDStr := strings.TrimSpace(c.PostForm("shop_id"))
	shopID, err := uuid.Parse(shopIDStr)
	if err != nil || shopID == uuid.Nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id required"})
		return
	}

	gpCanonical := strings.TrimSpace(c.PostForm("gp_canonical"))
	if gpCanonical == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "gp_canonical required"})
		return
	}

	sizeML, err := strconv.Atoi(strings.TrimSpace(c.PostForm("size_ml")))
	if err != nil || sizeML <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "size_ml must be a positive integer"})
		return
	}

	// Optional candidate set (refuse-out-of-set defense).
	candidates := []uuid.UUID{}
	if raw := strings.TrimSpace(c.PostForm("candidate_ids")); raw != "" {
		for _, part := range strings.Split(raw, ",") {
			id, err := uuid.Parse(strings.TrimSpace(part))
			if err == nil && id != uuid.Nil {
				candidates = append(candidates, id)
			}
		}
	}

	// File upload — accept "image" (preferred) or "file" (legacy).
	file, header, err := c.Request.FormFile("image")
	if err != nil {
		file, header, err = c.Request.FormFile("file")
	}
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image file required (form field 'image')"})
		return
	}
	defer file.Close()

	imageBytes, err := io.ReadAll(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read uploaded image"})
		return
	}
	contentType := header.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "image/jpeg"
	}

	h.logger.WithFields(logrus.Fields{
		"tenant_id":    tenantID,
		"shop_id":      shopID,
		"gp_canonical": gpCanonical,
		"size_ml":      sizeML,
		"image_bytes":  len(imageBytes),
		"candidates":   len(candidates),
	}).Info("[disambig] resolving past-purchase upload")

	result, err := h.service.ResolveDisambigFromPastPurchase(
		c.Request.Context(),
		tenantID, shopID,
		imageBytes, contentType,
		gpCanonical, sizeML,
		candidates,
	)
	if err != nil {
		h.logger.WithError(err).Error("[disambig] resolve failed")
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if result == nil || result.Action != "resolved" {
		// 422 lets Flutter render "couldn't disambiguate, pick manually"
		// without treating it as a server error.
		payload := gin.H{
			"action":         "no_match",
			"brand_resolved": "",
			"confidence":     0.0,
		}
		if result != nil {
			payload["brand_resolved"] = result.BrandResolved
			payload["confidence"] = result.Confidence
		}
		c.JSON(http.StatusUnprocessableEntity, payload)
		return
	}
	c.JSON(http.StatusOK, result)
}

// ResolveBatch handles POST /purchases/smart-purchase/disambig-batch.
//
// v1.0.223 — accepts one past-purchase image + a JSON array of queries
// (each = {row_index, gp_canonical, size_ml, candidate_product_ids?}).
// Backend extracts the image ONCE and resolves every query against the
// cached extraction. Returns a list of {row_index, result} preserving the
// caller's ordering so Flutter can patch its rows in a single response.
//
// Multipart form:
//   image    (file)    the shared past-purchase image (any size mix is OK;
//                       per-query size_ml gates which extraction lines are
//                       considered)
//   queries  (string)  JSON array, e.g.:
//                       [{"row_index":15,"gp_canonical":"M2 Remix Sup Green Apple","size_ml":180,"candidate_product_ids":["uuid1","uuid2"]},
//                        {"row_index":16,"gp_canonical":"M2 Remix Sup Orange","size_ml":180}]
//   shop_id  (uuid)    shop scope for alias learning
//
// Response: 200 OK with services.DisambigBatchResult. Per-row Action is
// either "resolved" or "no_match" — caller filters/handles each row.
func (h *SmartPurchaseDisambigHandler) ResolveBatch(c *gin.Context) {
	if h.service == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Purchase disambig not configured"})
		return
	}
	tenantID, terr := tenantUUIDFromContext(c)
	if terr != nil {
		c.JSON(terr.status, gin.H{"error": terr.msg})
		return
	}

	shopID, err := uuid.Parse(strings.TrimSpace(c.PostForm("shop_id")))
	if err != nil || shopID == uuid.Nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id required"})
		return
	}

	queriesRaw := strings.TrimSpace(c.PostForm("queries"))
	if queriesRaw == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "queries (JSON array) required"})
		return
	}

	// Accept the operator-facing shape (UUIDs as strings) and convert to
	// uuid.UUID for the service layer. v1.0.226 — added gp_expected_qty.
	type queryWire struct {
		RowIndex            int      `json:"row_index"`
		GPCanonical         string   `json:"gp_canonical"`
		SizeML              int      `json:"size_ml"`
		CandidateProductIDs []string `json:"candidate_product_ids"`
		GPExpectedQty       int      `json:"gp_expected_qty"`
	}
	var wire []queryWire
	if err := json.Unmarshal([]byte(queriesRaw), &wire); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "queries must be a JSON array: " + err.Error()})
		return
	}
	if len(wire) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "queries array is empty"})
		return
	}
	queries := make([]services.DisambigQuery, 0, len(wire))
	for _, w := range wire {
		gpCan := strings.TrimSpace(w.GPCanonical)
		if gpCan == "" || w.SizeML <= 0 {
			continue
		}
		candidates := make([]uuid.UUID, 0, len(w.CandidateProductIDs))
		for _, c := range w.CandidateProductIDs {
			id, err := uuid.Parse(strings.TrimSpace(c))
			if err == nil && id != uuid.Nil {
				candidates = append(candidates, id)
			}
		}
		queries = append(queries, services.DisambigQuery{
			RowIndex:            w.RowIndex,
			GPCanonical:         gpCan,
			SizeML:              w.SizeML,
			CandidateProductIDs: candidates,
			GPExpectedQty:       w.GPExpectedQty,
		})
	}
	if len(queries) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no valid queries (need gp_canonical + size_ml > 0)"})
		return
	}

	// v1.0.226 — multi-image + PDF upload. The Purcha gate accepts any of:
	//   • One JPG/PNG (legacy "image" or "file" form field)
	//   • N JPGs/PNGs (multi-page Purcha photo) via images[] form field
	//   • One PDF (multi-page scan); rendered to PNG pages via cv-sidecar
	// Pages are queued in upload order and Claude extracts brand+qty from
	// each. Per-page failures are non-fatal: at least one page must succeed.
	pages, perr := h.collectPagesFromForm(c)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": perr.Error()})
		return
	}
	if len(pages) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no images supplied (form field 'images' or 'image' or PDF)"})
		return
	}

	totalBytes := 0
	for _, p := range pages {
		totalBytes += len(p.Bytes)
	}
	h.logger.WithFields(logrus.Fields{
		"tenant_id":     tenantID,
		"shop_id":       shopID,
		"queries_count": len(queries),
		"page_count":    len(pages),
		"total_bytes":   totalBytes,
	}).Info("[disambig_batch] resolving past-purchase batch (v226 multi-page)")

	result, err := h.service.ResolveDisambigBatchMulti(
		c.Request.Context(),
		tenantID, shopID,
		pages,
		queries,
	)
	if err != nil {
		h.logger.WithError(err).Error("[disambig_batch] resolve failed")
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Need at least one resolution to be useful — if every row no_matched,
	// surface 422 so Flutter shows the same "pick manually" affordance as
	// the single-row endpoint does.
	statusCode := http.StatusOK
	if result == nil || result.ResolvedCount == 0 {
		statusCode = http.StatusUnprocessableEntity
	}
	c.JSON(statusCode, result)
}

// collectPagesFromForm walks the multipart form and gathers one or more
// pages for the Purcha-gate disambig flow.
//
// Form fields accepted (first non-empty wins, but all three may be used
// together — the result is a unioned list of pages in upload order):
//
//   • images   (one or more files) — multi-page Purcha photo
//   • image    (single file)       — legacy single-image form
//   • file     (single file)       — alternative single-image form
//
// PDFs are detected by content-type or %PDF magic bytes and rendered to
// PNG pages via cv-sidecar /pdf-to-pages. A failure to render the PDF
// returns a usable error.
//
// Returns ([], err) on hard failure; ([], nil) when no files were
// provided (handler decides whether that's a 400).
func (h *SmartPurchaseDisambigHandler) collectPagesFromForm(c *gin.Context) ([]services.DisambigPageInput, error) {
	pages := make([]services.DisambigPageInput, 0, 4)

	form, _ := c.MultipartForm()
	type formFile struct {
		filename    string
		contentType string
		bytes       []byte
	}
	files := make([]formFile, 0, 4)

	if form != nil {
		for _, key := range []string{"images", "images[]"} {
			for _, fh := range form.File[key] {
				f, err := fh.Open()
				if err != nil {
					return nil, err
				}
				b, rerr := io.ReadAll(f)
				_ = f.Close()
				if rerr != nil {
					return nil, rerr
				}
				files = append(files, formFile{
					filename:    fh.Filename,
					contentType: fh.Header.Get("Content-Type"),
					bytes:       b,
				})
			}
		}
	}
	// Legacy single-file fallbacks. We accept these even when `images`
	// was supplied so older Flutter clients can mix without breaking.
	for _, key := range []string{"image", "file"} {
		if file, header, err := c.Request.FormFile(key); err == nil {
			b, rerr := io.ReadAll(file)
			_ = file.Close()
			if rerr != nil {
				return nil, rerr
			}
			files = append(files, formFile{
				filename:    header.Filename,
				contentType: header.Header.Get("Content-Type"),
				bytes:       b,
			})
		}
	}

	for i, ff := range files {
		if len(ff.bytes) == 0 {
			continue
		}
		ct := ff.contentType
		if ct == "" {
			ct = "image/jpeg"
		}
		// PDF branch — render pages via cv-sidecar before pushing into
		// the page list.
		var firstFour []byte
		if len(ff.bytes) >= 4 {
			firstFour = ff.bytes[:4]
		}
		if services.IsPDFContentType(ct, firstFour) {
			rendered, err := services.RenderPDFViaCVSidecar(c.Request.Context(), ff.bytes)
			if err != nil {
				h.logger.WithError(err).WithField("file_index", i).Warn("[disambig_batch] PDF render failed — skipping file")
				continue
			}
			for _, p := range rendered {
				pages = append(pages, services.DisambigPageInput{
					Bytes:       p.PNGBytes,
					ContentType: "image/png",
					Source:      formatPDFPageSource(ff.filename, p.Index),
				})
			}
			continue
		}
		// Plain image.
		pages = append(pages, services.DisambigPageInput{
			Bytes:       ff.bytes,
			ContentType: ct,
			Source:      formatImageSource(ff.filename, i),
		})
	}
	return pages, nil
}

func formatPDFPageSource(filename string, pageIdx int) string {
	if filename == "" {
		filename = "purcha.pdf"
	}
	return filename + "#page=" + strconv.Itoa(pageIdx+1)
}

func formatImageSource(filename string, idx int) string {
	if filename == "" {
		return "image_" + strconv.Itoa(idx)
	}
	return filename
}

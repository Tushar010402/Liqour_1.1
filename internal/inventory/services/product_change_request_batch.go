package services

// v1.0.344 — Combined photo/name/MRP change-requests.
//
// Extends the proven product_change_requests workflow (product_change_request.go)
// so an AI-Purchase photo-onboarding session becomes ONE reviewable request on
// the web admin portal. Each product captured in a session writes (or merges
// into) a PCR row keyed by a shared batch_id:
//
//   - High confidence (>= photoAutoApplyConfidence): the field (name and/or MRP)
//     is applied to the product immediately by the verify handler, and recorded
//     here as auto_applied — the portal shows it live with a Revert action.
//   - Low confidence: the field is recorded as a PENDING proposal; the product
//     is NOT changed until an admin approves it (bulk or per-item) on the portal
//     or the operator taps Use on the mobile capture screen.
//
// Front photo proposes the NAME; back photo proposes the MRP. Both calls merge
// into the single batch+product row so one product = one combined-request line.

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// photoAutoApplyConfidence — at/above this the vision read is trusted enough to
// apply immediately ("auto-apply confident, queue the rest"). Mirrors the
// existing nameRewriteConfidence used by VerifyProduct.
const photoAutoApplyConfidence = 0.6

// PhotoChangeInput is one face's worth of a photo-derived proposal. The verify
// handler fills it after a Gemini read; Applied says whether the handler already
// wrote this face's field onto the product (true only when confident).
type PhotoChangeInput struct {
	TenantID        uuid.UUID
	ShopID          *uuid.UUID
	ProductID       uuid.UUID
	BatchID         uuid.UUID
	Face            string // "front" (name) | "back" (mrp)
	CurrentName     string
	ProposedName    string
	CurrentMRP      float64
	ProposedMRP     float64
	Confidence      float64
	Applied         bool   // this face's field was auto-applied to the product
	PhotoURL        string // v1.0.349 — the saved label photo for this face
	RequestedByID   uuid.UUID
	RequestedByName string
}

// PhotoRenameWouldDuplicate reports whether applying a confident photo read's
// name/identity to THIS product would collide with a DIFFERENT product that
// already exists at the same shop and physical size — the wrong-image /
// would-be-duplicate case. Real trigger (Mahua Khera 2026-06-03): a garbled
// "imjum - 180ml (Quarter)" was about to be auto-renamed to "M2 Magic Moments
// Superior Vodka", which already exists at 180ml — minting a duplicate and
// burying imjum's 101 bottles under the wrong identity. When this returns true
// the caller must NOT auto-apply the rename; it queues the change for review.
//
// Two OR'd signals, size-scoped via normalizeSizeText so "180ML" == "180ml
// (Quarter)":
//   - catalog identity (strong, reliable): another product already carries the
//     saas_brand the photo resolved to (masterBrandID); or
//   - name (fallback for un-anchored reads): another product's normalized name
//     equals — or begins with — the proposed normalized name (existing names
//     often carry a "- <size>" suffix the proposal lacks).
//
// The asymmetry is deliberate: a false positive merely queues a legitimate
// rename for one approval click, while a false negative is a silent duplicate /
// mis-identified stock — so the name signal is permissive. On any DB error it
// returns false (never block the happy path on a query failure).
func PhotoRenameWouldDuplicate(db *gorm.DB, tenantID, shopID, productID uuid.UUID, size, masterBrandID, proposedName string) (bool, string, []uuid.UUID) {
	targetML := normalizeSizeText(size)
	var sbTarget *uuid.UUID
	if mb := strings.TrimSpace(masterBrandID); mb != "" {
		if id, e := uuid.Parse(mb); e == nil {
			sbTarget = &id
		}
	}
	propN := normalizeForMatch(proposedName)

	type prow struct {
		ID          uuid.UUID  `gorm:"column:id"`
		Name        string     `gorm:"column:name"`
		Size        string     `gorm:"column:size"`
		SaasBrandID *uuid.UUID `gorm:"column:saas_brand_id"`
		FrontImage  string     `gorm:"column:front_image_url"`
		BackImage   string     `gorm:"column:back_image_url"`
	}
	var rows []prow
	if err := db.Table("products").
		Select("id, name, size, saas_brand_id, front_image_url, back_image_url").
		Where("tenant_id = ? AND shop_id = ? AND id <> ? AND deleted_at IS NULL", tenantID, shopID, productID).
		Scan(&rows).Error; err != nil {
		return false, "", nil // never block on a query error
	}
	var consolidate []uuid.UUID
	for _, r := range rows {
		// Physical size must match (skip the row only when BOTH sizes are known
		// and differ — an unknown size on either side is not a safe exclusion).
		if targetML > 0 {
			if rML := normalizeSizeText(r.Size); rML > 0 && rML != targetML {
				continue
			}
		}
		matchedBrand := sbTarget != nil && r.SaasBrandID != nil && *r.SaasBrandID == *sbTarget
		matchedName := false
		if !matchedBrand && len(propN) >= 8 {
			rn := normalizeForMatch(r.Name)
			// Collide on: exact match; existing == proposed + a suffix (existing
			// name carries a trailing "- <size>"); or proposed == existing + a
			// suffix when the existing base is itself specific (≥12 chars), e.g.
			// existing "M2 Magic Moments Superior" vs proposed "...Superior Vodka".
			matchedName = rn == propN ||
				strings.HasPrefix(rn, propN) ||
				(len(rn) >= 12 && strings.HasPrefix(propN, rn))
		}
		if !matchedBrand && !matchedName {
			continue
		}
		// v1.0.389 — INTELLIGENT GUARD. A collision with an EMPTY, UNUSED STRAY
		// (0 stock + no photo + never sold) is NOT a real duplicate to protect —
		// it's leftover clutter (typically an auto-onboard SKU from a cancelled
		// purchase) that was BLOCKING the legit photo-rename of the REAL product.
		// Don't block; mark it for consolidation (caller soft-deletes it) so the
		// real photographed product takes the identity. Only a candidate that has
		// stock, a photo, OR sales blocks (queues for review) — a genuine product.
		if isEmptyStrayProduct(db, tenantID, shopID, r.ID, r.FrontImage, r.BackImage) {
			consolidate = append(consolidate, r.ID)
			continue
		}
		kind := "name"
		if matchedBrand {
			kind = "brand"
		}
		return true, fmt.Sprintf("a different product (%q) with this %s and size already exists", r.Name, kind), nil
	}
	return false, "", consolidate
}

// isEmptyStrayProduct reports whether a product is unused leftover clutter at
// this shop: 0 stock, no front/back photo, and never sold. Such a row must
// never block a legitimate photo-rename of the REAL (photographed/stocked)
// product — it gets consolidated (soft-deleted) instead. Conservative on
// purpose: stock OR a photo OR any sale ⇒ it's a real product, not a stray.
// v1.0.389.
func isEmptyStrayProduct(db *gorm.DB, tenantID, shopID, productID uuid.UUID, frontImage, backImage string) bool {
	if strings.TrimSpace(frontImage) != "" || strings.TrimSpace(backImage) != "" {
		return false
	}
	var stock int64
	db.Table("stocks").
		Where("tenant_id = ? AND shop_id = ? AND product_id = ? AND deleted_at IS NULL", tenantID, shopID, productID).
		Select("COALESCE(SUM(quantity), 0)").Scan(&stock)
	if stock > 0 {
		return false
	}
	var sales int64
	db.Table("daily_sales_items").Where("product_id = ?", productID).Count(&sales)
	return sales == 0
}

// RecordPhotoChangeRequest upserts the combined-request row for one product in a
// capture batch. Standalone (takes *gorm.DB) so the verify handler can call it
// without holding an EnhancedProductService. Returns nil and writes nothing when
// the face carries no actual change (e.g. a confident read that matches the
// current name) — we never queue a no-op for an admin to review.
func RecordPhotoChangeRequest(db *gorm.DB, in PhotoChangeInput) (uuid.UUID, error) {
	front := strings.ToLower(strings.TrimSpace(in.Face)) != "back"
	proposedName := strings.TrimSpace(in.ProposedName)

	// Does this face actually propose a change?
	nameChange := front && proposedName != "" && !strings.EqualFold(proposedName, strings.TrimSpace(in.CurrentName))
	mrpChange := !front && in.ProposedMRP > 0 && in.ProposedMRP != in.CurrentMRP
	if !nameChange && !mrpChange {
		return uuid.Nil, nil
	}

	var resultID uuid.UUID
	err := db.Transaction(func(tx *gorm.DB) error {
		// Prefer a row already in THIS batch (front+back of the same product
		// merge into one line). Otherwise adopt any open pending row for this
		// product so we never collide with idx_pcr_one_open_per_product.
		var row ProductChangeRequest
		found := tx.Where("tenant_id = ? AND product_id = ? AND deleted_at IS NULL", in.TenantID, in.ProductID).
			Where("batch_id = ? OR status = ?", in.BatchID, "pending").
			Order("requested_at DESC").
			First(&row).Error == nil

		conf := in.Confidence
		now := time.Now()
		batch := in.BatchID

		if !found {
			row = ProductChangeRequest{
				TenantID:        in.TenantID,
				ShopID:          in.ShopID,
				ProductID:       in.ProductID,
				BatchID:         &batch,
				Status:          "pending",
				Source:          "photo_verify",
				RequestedByID:   in.RequestedByID,
				RequestedByName: in.RequestedByName,
				RequestedAt:     now,
				CurrentName:     strings.TrimSpace(in.CurrentName),
				CurrentMRP:      in.CurrentMRP,
				Confidence:      &conf,
			}
		}

		// Merge this face's proposal.
		if nameChange {
			row.ProposedName = proposedName
			if row.CurrentName == "" {
				row.CurrentName = strings.TrimSpace(in.CurrentName)
			}
			if in.Applied {
				row.NameApplied = true
			}
		}
		if mrpChange {
			row.ProposedMRP = in.ProposedMRP
			if row.CurrentMRP == 0 {
				row.CurrentMRP = in.CurrentMRP
			}
			if in.Applied {
				row.MRPApplied = true
			}
		}
		row.Confidence = &conf
		row.BatchID = &batch
		if row.Source == "" {
			row.Source = "photo_verify"
		}
		// v1.0.349 — snapshot the captured photo for this face onto the request
		// (front drives the name, back the MRP). Only overwrite the face we just
		// captured, so a later back capture never wipes the stored front photo.
		if photoURL := strings.TrimSpace(in.PhotoURL); photoURL != "" {
			if front {
				row.SourceFrontImageURL = photoURL
			} else {
				row.SourceBackImageURL = photoURL
			}
		}

		// Derive change_kind / status / auto_applied from the merged row.
		row.ChangeKind, row.Status, row.AutoApplied = photoRowState(
			row.ProposedName, row.CurrentName, row.ProposedMRP, row.CurrentMRP, row.NameApplied, row.MRPApplied)
		if row.Status == "approved" {
			row.ApprovedAt = &now
			row.ApprovedByName = "AI (auto)"
		} else {
			row.ApprovedAt = nil
			row.ApprovedByName = ""
		}
		row.UpdatedAt = now

		if found {
			resultID = row.ID
			return tx.Model(&ProductChangeRequest{}).Where("id = ?", row.ID).
				Updates(map[string]interface{}{
					"shop_id":           row.ShopID,
					"batch_id":          row.BatchID,
					"change_kind":       row.ChangeKind,
					"proposed_name":     row.ProposedName,
					"current_name":      row.CurrentName,
					"proposed_mrp":      row.ProposedMRP,
					"current_mrp":       row.CurrentMRP,
					"confidence":        row.Confidence,
					"auto_applied":      row.AutoApplied,
					"name_applied":      row.NameApplied,
					"mrp_applied":       row.MRPApplied,
					"status":            row.Status,
					"approved_at":       row.ApprovedAt,
					"approved_by_name":  row.ApprovedByName,
					"source":                  row.Source,
					"source_front_image_url":  row.SourceFrontImageURL,
					"source_back_image_url":   row.SourceBackImageURL,
					"requested_by_id":         in.RequestedByID,
					"requested_by_name":       in.RequestedByName,
					"updated_at":              now,
				}).Error
		}
		if err := tx.Create(&row).Error; err != nil {
			return err
		}
		resultID = row.ID
		return nil
	})
	return resultID, err
}

// photoRowState derives a merged combined-request row's change_kind, status and
// auto_applied flag from its proposals and per-field applied flags. Pure (no DB)
// so it's unit-tested. Rules:
//   - change_kind names whatever the row PROPOSES (name and/or mrp).
//   - status is "pending" while any REAL change (proposal that differs from the
//     current value) has not yet been auto-applied; otherwise "approved".
//   - auto_applied is true once any field was applied at capture time.
func photoRowState(proposedName, currentName string, proposedMRP, currentMRP float64, nameApplied, mrpApplied bool) (changeKind, status string, autoApplied bool) {
	hasNameProposal := strings.TrimSpace(proposedName) != ""
	hasMRPProposal := proposedMRP > 0
	switch {
	case hasNameProposal && hasMRPProposal:
		changeKind = "name_mrp"
	case hasNameProposal:
		changeKind = "name"
	case hasMRPProposal:
		changeKind = "mrp"
	default:
		changeKind = "photo"
	}

	pendingName := hasNameProposal && !nameApplied &&
		!strings.EqualFold(strings.TrimSpace(proposedName), strings.TrimSpace(currentName))
	pendingMRP := hasMRPProposal && !mrpApplied && proposedMRP != currentMRP
	autoApplied = nameApplied || mrpApplied
	if pendingName || pendingMRP {
		status = "pending"
	} else {
		status = "approved"
	}
	return
}

// PhotoChangeBatchResponse is one combined request on the portal.
type PhotoChangeBatchResponse struct {
	BatchID         string                         `json:"batch_id"`
	ShopID          string                         `json:"shop_id,omitempty"`
	RequestedByName string                         `json:"requested_by_name"`
	RequestedAt     string                         `json:"requested_at"`
	Total           int                            `json:"total"`
	Pending         int                            `json:"pending"`
	Approved        int                            `json:"approved"`
	Rejected        int                            `json:"rejected"`
	AutoApplied     int                            `json:"auto_applied"`
	Items           []ProductChangeRequestResponse `json:"items"`
}

// ListPhotoChangeBatches groups batch_id'd PCR rows into combined requests.
// status filters the BATCHES by whether they still contain pending items:
// "pending" = batches with >=1 pending item; "" = all photo batches.
func (s *EnhancedProductService) ListPhotoChangeBatches(
	ctx context.Context, tenantID uuid.UUID, shopID, status string,
) ([]PhotoChangeBatchResponse, error) {
	q := s.db.Model(&ProductChangeRequest{}).
		Where("tenant_id = ? AND batch_id IS NOT NULL AND deleted_at IS NULL", tenantID)
	if shopID != "" {
		if sid, e := uuid.Parse(shopID); e == nil {
			q = q.Where("shop_id = ?", sid)
		}
	}
	var rows []ProductChangeRequest
	if err := q.Order("requested_at DESC").Find(&rows).Error; err != nil {
		return nil, err
	}

	order := []string{}
	byBatch := map[string]*PhotoChangeBatchResponse{}
	for _, r := range rows {
		if r.BatchID == nil {
			continue
		}
		key := r.BatchID.String()
		b, ok := byBatch[key]
		if !ok {
			b = &PhotoChangeBatchResponse{
				BatchID:         key,
				RequestedByName: r.RequestedByName,
				RequestedAt:     r.RequestedAt.Format(time.RFC3339),
				Items:           []ProductChangeRequestResponse{},
			}
			if r.ShopID != nil {
				b.ShopID = r.ShopID.String()
			}
			byBatch[key] = b
			order = append(order, key)
		}
		b.Items = append(b.Items, s.toPCRResponse(r, s.productInfo(tenantID, r.ProductID)))
		b.Total++
		switch r.Status {
		case "pending":
			b.Pending++
		case "approved":
			b.Approved++
		case "rejected":
			b.Rejected++
		}
		if r.AutoApplied {
			b.AutoApplied++
		}
	}

	out := make([]PhotoChangeBatchResponse, 0, len(order))
	for _, k := range order {
		b := byBatch[k]
		if status == "pending" && b.Pending == 0 {
			continue
		}
		out = append(out, *b)
	}
	return out, nil
}

// ApproveBatch approves every still-pending item in a combined request. Returns
// (approvedCount, error). Role-gated like ApproveProductChange.
func (s *EnhancedProductService) ApproveBatch(
	ctx context.Context, batchID, tenantID, approverID uuid.UUID, approverRole string,
) (int, error) {
	if !s.pcrIsPrivileged(approverRole) {
		return 0, fmt.Errorf("only admin or manager can approve product changes")
	}
	var ids []uuid.UUID
	if err := s.db.Model(&ProductChangeRequest{}).
		Where("tenant_id = ? AND batch_id = ? AND status = 'pending' AND deleted_at IS NULL", tenantID, batchID).
		Pluck("id", &ids).Error; err != nil {
		return 0, err
	}
	n := 0
	for _, id := range ids {
		if _, err := s.ApproveProductChange(ctx, id, tenantID, approverID, approverRole); err != nil {
			return n, fmt.Errorf("approve %s: %w", id, err)
		}
		n++
	}
	return n, nil
}

// RejectBatch rejects every still-pending item in a combined request.
func (s *EnhancedProductService) RejectBatch(
	ctx context.Context, batchID, tenantID, rejectorID uuid.UUID, approverRole, reason string,
) (int, error) {
	if !s.pcrIsPrivileged(approverRole) {
		return 0, fmt.Errorf("only admin or manager can reject product changes")
	}
	var ids []uuid.UUID
	if err := s.db.Model(&ProductChangeRequest{}).
		Where("tenant_id = ? AND batch_id = ? AND status = 'pending' AND deleted_at IS NULL", tenantID, batchID).
		Pluck("id", &ids).Error; err != nil {
		return 0, err
	}
	n := 0
	for _, id := range ids {
		if err := s.RejectProductChange(ctx, id, tenantID, rejectorID, reason); err != nil {
			return n, fmt.Errorf("reject %s: %w", id, err)
		}
		n++
	}
	return n, nil
}

// RevertProductChange undoes an auto-applied change: it restores the snapshotted
// current_name / current_mrp onto the product and marks the request 'reverted'.
// This is the portal's escape hatch for a confident misread. Role-gated.
func (s *EnhancedProductService) RevertProductChange(
	ctx context.Context, id, tenantID, actorID uuid.UUID, actorRole string,
) (*ProductChangeRequestResponse, error) {
	if !s.pcrIsPrivileged(actorRole) {
		return nil, fmt.Errorf("only admin or manager can revert product changes")
	}
	actorName := s.userDisplayName(tenantID, actorID)
	txErr := s.db.Transaction(func(tx *gorm.DB) error {
		var r ProductChangeRequest
		if err := tx.Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
			First(&r).Error; err != nil {
			return fmt.Errorf("change request not found")
		}
		if !r.AutoApplied {
			return fmt.Errorf("only an auto-applied change can be reverted")
		}
		if r.Status == "reverted" {
			return fmt.Errorf("request is already reverted")
		}
		now := time.Now()
		updates := map[string]interface{}{}
		if r.NameApplied && strings.TrimSpace(r.CurrentName) != "" {
			updates["name"] = r.CurrentName
			updates["display_name"] = r.CurrentName
			updates["display_name_bold_start"] = nil
			updates["display_name_bold_length"] = nil
		}
		if r.MRPApplied && r.CurrentMRP > 0 {
			updates["mrp"] = r.CurrentMRP
			updates["last_mrp_change_at"] = now
			updates["last_mrp_change_by_id"] = actorID
			updates["last_mrp_change_by_name"] = actorName
			updates["last_mrp_change_previous"] = r.ProposedMRP
		}
		if len(updates) > 0 {
			if err := tx.Table("products").
				Where("id = ? AND tenant_id = ?", r.ProductID, tenantID).
				Updates(updates).Error; err != nil {
				return err
			}
		}
		return tx.Model(&ProductChangeRequest{}).Where("id = ?", r.ID).
			Updates(map[string]interface{}{
				"status":           "reverted",
				"approved_by_id":   actorID,
				"approved_by_name": actorName,
				"approved_at":      now,
				"updated_at":       now,
			}).Error
	})
	if txErr != nil {
		return nil, txErr
	}
	return s.GetProductChangeRequest(ctx, id, tenantID)
}

package services

// v1.0.253 — Product photo+MRP change-request approval workflow.
//
// Every role can use the inventory Brand Photos & MRP editor. Photos apply
// immediately for all (handled by VerifyProduct, unchanged). An MRP change by
// a non-admin/manager becomes a PENDING request that admin/manager approve —
// mirroring the Stock Setup pending→approve/reject pattern. All logic is
// isolated here so EnhancedProductService.UpdateProductPricing stays untouched
// (lowest risk). Model lives in the inventory package (NOT pkg/shared) so only
// the inventory service rebuilds.

import (
	"context"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// ProductChangeRequest maps the product_change_requests table
// (migration 20260515_product_change_requests.sql). Explicit gorm column tags
// per the v132/v246 GORM-name-mangling lesson.
type ProductChangeRequest struct {
	ID              uuid.UUID  `json:"id" gorm:"column:id;type:uuid;primaryKey;default:gen_random_uuid()"`
	TenantID        uuid.UUID  `json:"tenant_id" gorm:"column:tenant_id;type:uuid;not null"`
	ShopID          *uuid.UUID `json:"shop_id,omitempty" gorm:"column:shop_id;type:uuid"`
	ProductID       uuid.UUID  `json:"product_id" gorm:"column:product_id;type:uuid;not null"`
	ProposedMRP     float64    `json:"proposed_mrp" gorm:"column:proposed_mrp;type:numeric(10,2)"`
	CurrentMRP      float64    `json:"current_mrp" gorm:"column:current_mrp;type:numeric(10,2)"`
	Status          string     `json:"status" gorm:"column:status;default:'pending'"`
	RequestedByID   uuid.UUID  `json:"requested_by_id" gorm:"column:requested_by_id;type:uuid;not null"`
	RequestedByName string     `json:"requested_by_name" gorm:"column:requested_by_name"`
	RequestedAt     time.Time  `json:"requested_at" gorm:"column:requested_at"`
	ApprovedByID    *uuid.UUID `json:"approved_by_id,omitempty" gorm:"column:approved_by_id;type:uuid"`
	ApprovedByName  string     `json:"approved_by_name,omitempty" gorm:"column:approved_by_name"`
	ApprovedAt      *time.Time `json:"approved_at,omitempty" gorm:"column:approved_at"`
	RejectionReason string     `json:"rejection_reason,omitempty" gorm:"column:rejection_reason"`
	CreatedAt       time.Time  `json:"created_at" gorm:"column:created_at"`
	UpdatedAt       time.Time  `json:"updated_at" gorm:"column:updated_at"`
	DeletedAt       *time.Time `json:"-" gorm:"column:deleted_at"`

	// v1.0.344 — combined photo/name/MRP request fields (migration
	// 20260602_pcr_photo_name_batch.sql). change_kind defaults to 'mrp' so
	// legacy rows behave exactly as before. The photo-onboarding flow groups
	// every product captured in one session under a single batch_id (= one
	// combined request on the web portal) and tracks which fields were
	// auto-applied at high confidence vs. left pending for review.
	ChangeKind   string     `json:"change_kind,omitempty" gorm:"column:change_kind;default:'mrp'"`
	ProposedName string     `json:"proposed_name,omitempty" gorm:"column:proposed_name"`
	CurrentName  string     `json:"current_name,omitempty" gorm:"column:current_name"`
	BatchID      *uuid.UUID `json:"batch_id,omitempty" gorm:"column:batch_id;type:uuid"`
	Confidence   *float64   `json:"confidence,omitempty" gorm:"column:confidence;type:numeric(4,3)"`
	AutoApplied  bool       `json:"auto_applied" gorm:"column:auto_applied;default:false"`
	NameApplied  bool       `json:"name_applied" gorm:"column:name_applied;default:false"`
	MRPApplied   bool       `json:"mrp_applied" gorm:"column:mrp_applied;default:false"`
	Source       string     `json:"source,omitempty" gorm:"column:source"`

	// v1.0.349 — the captured label photo(s) that drove this proposal, snapshotted
	// at request time (migration 20260603_pcr_source_images.sql). Front photo reads
	// the NAME, back photo reads the MRP. Stored on the request (not just the live
	// product) so the Photo Reviews page always shows the exact image the read came
	// from, even after the product's photo is later replaced.
	SourceFrontImageURL string `json:"source_front_image_url,omitempty" gorm:"column:source_front_image_url"`
	SourceBackImageURL  string `json:"source_back_image_url,omitempty" gorm:"column:source_back_image_url"`
}

func (ProductChangeRequest) TableName() string { return "product_change_requests" }

// PricingActor is who is changing pricing — role decides direct-vs-pending,
// id/name feed the MRP-audit chip. Never trust the client for role; the
// handler fills this from the JWT-derived gin context.
type PricingActor struct {
	Role     string
	UserID   uuid.UUID
	UserName string
	ShopID   *uuid.UUID
}

// ProductChangeRequestResponse is the admin/app list+detail shape.
type ProductChangeRequestResponse struct {
	ID              string  `json:"id"`
	ProductID       string  `json:"product_id"`
	ProductName     string  `json:"product_name"`
	Size            string  `json:"size"`
	ShopID          string  `json:"shop_id,omitempty"`
	CurrentMRP      float64 `json:"current_mrp"`
	ProposedMRP     float64 `json:"proposed_mrp"`
	Status          string  `json:"status"`
	RequestedByName string  `json:"requested_by_name"`
	RequestedByID   string  `json:"requested_by_id"`
	RequestedAt     string  `json:"requested_at"`
	ApprovedByName  string  `json:"approved_by_name,omitempty"`
	ApprovedAt      string  `json:"approved_at,omitempty"`
	RejectionReason string  `json:"rejection_reason,omitempty"`

	// v1.0.344 — combined request fields. ChangeKind tells the portal which of
	// name / MRP this row proposes; CurrentName→ProposedName mirror the
	// CurrentMRP→ProposedMRP old→new display. AutoApplied (+ NameApplied /
	// MRPApplied) flag a high-confidence change that's already live and so
	// offers Revert instead of Approve.
	ChangeKind   string   `json:"change_kind,omitempty"`
	CurrentName  string   `json:"current_name,omitempty"`
	ProposedName string   `json:"proposed_name,omitempty"`
	BatchID      string   `json:"batch_id,omitempty"`
	Confidence   *float64 `json:"confidence,omitempty"`
	AutoApplied  bool     `json:"auto_applied"`
	NameApplied  bool     `json:"name_applied"`
	MRPApplied   bool     `json:"mrp_applied"`

	// v1.0.349 — captured label photo(s) the read came from, so the reviewer can
	// eyeball the bottle against the proposed name/MRP. Empty for legacy rows.
	FrontImageURL string `json:"front_image_url,omitempty"`
	BackImageURL  string `json:"back_image_url,omitempty"`

	// v1.0.352 — distinguishes an AI photo capture ("photo_verify") from a manual
	// pricing-editor edit (empty). Lets the portal label "From photo" vs
	// "Manual edit" instead of inferring it.
	Source string `json:"source,omitempty"`
}

func (s *EnhancedProductService) pcrIsPrivileged(role string) bool {
	role = strings.ToLower(strings.TrimSpace(role))
	return role == models.RoleAdmin || role == models.RoleManager
}

// pcrMRPEqual compares two MRP values at the product_change_requests column
// precision (numeric(10,2)). Plain float equality is unsafe — the same rupee
// value can differ in the low bits after a JSON round-trip vs a DB scan — so we
// compare rounded paise. Used to never queue a "change" that doesn't move the
// price (mirrors the photo path's ProposedMRP != CurrentMRP guard).
func pcrMRPEqual(a, b float64) bool {
	return math.Round(a*100) == math.Round(b*100)
}

// userDisplayName resolves "First Last" for the MRP-audit chip / queue. Cheap,
// best-effort — empty name is acceptable (chip just shows blank).
func (s *EnhancedProductService) userDisplayName(tenantID, userID uuid.UUID) string {
	var u struct {
		First string `gorm:"column:first_name"`
		Last  string `gorm:"column:last_name"`
	}
	if err := s.db.Table("users").
		Select("first_name, last_name").
		Where("id = ? AND tenant_id = ?", userID, tenantID).
		Scan(&u).Error; err != nil {
		return ""
	}
	return strings.TrimSpace(strings.TrimSpace(u.First) + " " + strings.TrimSpace(u.Last))
}

// SubmitOrApplyPricing is the role-aware pricing entrypoint the handler calls
// instead of UpdateProductPricing directly.
//   - non-admin/manager + an MRP change → upsert ONE open pending request
//     (no product mutation), return queuedPending=true.
//   - admin/manager (or no MRP change) → apply via the untouched
//     UpdateProductPricing, then, when MRP actually changed, write the
//     last_mrp_change_* audit chip (pre-existing gap this path never filled).
func (s *EnhancedProductService) SubmitOrApplyPricing(
	ctx context.Context, productID, tenantID uuid.UUID, req UpdatePricingRequest, actor PricingActor,
) (product *models.Product, queuedPending bool, err error) {

	var current models.Product
	if dbErr := s.db.Where("id = ? AND tenant_id = ?", productID, tenantID).First(&current).Error; dbErr != nil {
		return nil, false, fmt.Errorf("product not found")
	}
	prevMRP := current.MRP

	// Gate ONLY on MRP. A non-privileged actor changing MRP → pending.
	if req.MRP != nil && !s.pcrIsPrivileged(actor.Role) {
		// v1.0.352 — NO-OP GUARD. A "save" that doesn't move the MRP must never
		// create (or clobber) a pending request — that produced the ₹350→₹350
		// junk rows in the admin queue. Return the normal success triple so the
		// handler emits "updated successfully" (NOT queuedPending=true, which
		// would wrongly tell staff it was "submitted for approval"). Leaving any
		// existing legitimate pending request untouched here is intentional and
		// strictly more conservative than the old unconditional upsert.
		if pcrMRPEqual(*req.MRP, prevMRP) {
			return &current, false, nil
		}
		name := actor.UserName
		if name == "" {
			name = s.userDisplayName(tenantID, actor.UserID)
		}
		// Upsert one open pending request per (tenant, product). The partial
		// unique index idx_pcr_one_open_per_product guards races.
		txErr := s.db.Transaction(func(tx *gorm.DB) error {
			var existing ProductChangeRequest
			find := tx.Where("tenant_id = ? AND product_id = ? AND status = 'pending' AND deleted_at IS NULL",
				tenantID, productID).First(&existing)
			if find.Error == nil {
				return tx.Model(&ProductChangeRequest{}).
					Where("id = ?", existing.ID).
					Updates(map[string]interface{}{
						"proposed_mrp":      *req.MRP,
						"current_mrp":       prevMRP,
						"requested_by_id":   actor.UserID,
						"requested_by_name": name,
						"requested_at":      time.Now(),
						"updated_at":        time.Now(),
					}).Error
			}
			pcr := ProductChangeRequest{
				TenantID:        tenantID,
				ShopID:          actor.ShopID,
				ProductID:       productID,
				ProposedMRP:     *req.MRP,
				CurrentMRP:      prevMRP,
				Status:          "pending",
				RequestedByID:   actor.UserID,
				RequestedByName: name,
				RequestedAt:     time.Now(),
			}
			return tx.Create(&pcr).Error
		})
		if txErr != nil {
			return nil, false, fmt.Errorf("failed to submit MRP change for approval: %w", txErr)
		}
		return &current, true, nil
	}

	// Privileged (or no MRP change): apply via the untouched core method.
	applied, applyErr := s.UpdateProductPricing(ctx, productID, tenantID, req)
	if applyErr != nil {
		return nil, false, applyErr
	}
	// Fill the MRP-audit chip when MRP actually changed (every other write
	// path does this; the direct pricing path historically did not).
	if req.MRP != nil && *req.MRP != prevMRP {
		name := actor.UserName
		if name == "" {
			name = s.userDisplayName(tenantID, actor.UserID)
		}
		now := time.Now()
		_ = s.db.Model(&models.Product{}).
			Where("id = ? AND tenant_id = ?", productID, tenantID).
			Updates(map[string]interface{}{
				"last_mrp_change_at":       now,
				"last_mrp_change_by_id":    actor.UserID,
				"last_mrp_change_by_name":  name,
				"last_mrp_change_previous": prevMRP,
			}).Error
	}
	return applied, false, nil
}

func (s *EnhancedProductService) toPCRResponse(p ProductChangeRequest, info pcrProductInfo) ProductChangeRequestResponse {
	// Photo to show the reviewer: prefer the per-request snapshot (v1.0.349, the
	// exact image that drove a photo read); otherwise fall back to the product's
	// CURRENT label photo so the reviewer can always see the bottle for context —
	// on manual MRP edits too. v1.0.354: fallback is unconditional (was gated to
	// photo_verify). The "From photo" vs "Manual edit" badge is driven by Source,
	// NOT by image presence, so a manual row showing the product photo is still
	// correctly labelled "Manual edit". Rows whose product has no photo stay empty.
	frontURL := p.SourceFrontImageURL
	backURL := p.SourceBackImageURL
	if frontURL == "" {
		frontURL = info.FrontURL
	}
	if backURL == "" {
		backURL = info.BackURL
	}
	r := ProductChangeRequestResponse{
		ID:              p.ID.String(),
		ProductID:       p.ProductID.String(),
		ProductName:     info.Name,
		Size:            info.Size,
		CurrentMRP:      p.CurrentMRP,
		ProposedMRP:     p.ProposedMRP,
		Status:          p.Status,
		RequestedByName: p.RequestedByName,
		RequestedByID:   p.RequestedByID.String(),
		RequestedAt:     p.RequestedAt.Format(time.RFC3339),
		ApprovedByName:  p.ApprovedByName,
		RejectionReason: p.RejectionReason,
		ChangeKind:      p.ChangeKind,
		CurrentName:     p.CurrentName,
		ProposedName:    p.ProposedName,
		Confidence:      p.Confidence,
		AutoApplied:     p.AutoApplied,
		NameApplied:     p.NameApplied,
		MRPApplied:      p.MRPApplied,
		FrontImageURL:   frontURL,
		BackImageURL:    backURL,
		Source:          p.Source,
	}
	if p.BatchID != nil {
		r.BatchID = p.BatchID.String()
	}
	if p.ShopID != nil {
		r.ShopID = p.ShopID.String()
	}
	if p.ApprovedAt != nil {
		r.ApprovedAt = p.ApprovedAt.Format(time.RFC3339)
	}
	return r
}

// ListProductChangeRequests — admin/app queue. status optional ("" = all).
func (s *EnhancedProductService) ListProductChangeRequests(
	ctx context.Context, tenantID uuid.UUID, shopID, status string, page, pageSize int,
) (map[string]interface{}, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 200 {
		pageSize = 50
	}
	q := s.db.Model(&ProductChangeRequest{}).
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID)
	if status != "" {
		q = q.Where("status = ?", status)
	}
	if shopID != "" {
		if sid, e := uuid.Parse(shopID); e == nil {
			q = q.Where("shop_id = ?", sid)
		}
	}
	var total int64
	q.Count(&total)
	var rows []ProductChangeRequest
	if err := q.Order("requested_at DESC").
		Limit(pageSize).Offset((page - 1) * pageSize).
		Find(&rows).Error; err != nil {
		return nil, err
	}
	out := make([]ProductChangeRequestResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, s.toPCRResponse(r, s.productInfo(tenantID, r.ProductID)))
	}
	return map[string]interface{}{
		"requests": out, "total": total, "page": page, "page_size": pageSize,
	}, nil
}

// pcrProductInfo is the product context a review row needs: display name/size,
// plus the product's CURRENT label photos so a photo-driven request can fall back
// to them when it predates per-request photo snapshotting (v1.0.349).
type pcrProductInfo struct {
	Name     string `gorm:"column:name"`
	Size     string `gorm:"column:size"`
	FrontURL string `gorm:"column:front_image_url"`
	BackURL  string `gorm:"column:back_image_url"`
}

func (s *EnhancedProductService) productInfo(tenantID, productID uuid.UUID) pcrProductInfo {
	var p pcrProductInfo
	s.db.Table("products").Select("name, size, front_image_url, back_image_url").
		Where("id = ? AND tenant_id = ?", productID, tenantID).Scan(&p)
	return p
}

func (s *EnhancedProductService) GetProductChangePendingCount(
	ctx context.Context, tenantID uuid.UUID, shopID string,
) (int64, error) {
	q := s.db.Model(&ProductChangeRequest{}).
		Where("tenant_id = ? AND status = 'pending' AND deleted_at IS NULL", tenantID)
	if shopID != "" {
		if sid, e := uuid.Parse(shopID); e == nil {
			q = q.Where("shop_id = ?", sid)
		}
	}
	var n int64
	err := q.Count(&n).Error
	return n, err
}

func (s *EnhancedProductService) GetProductChangeRequest(
	ctx context.Context, id, tenantID uuid.UUID,
) (*ProductChangeRequestResponse, error) {
	var r ProductChangeRequest
	if err := s.db.Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&r).Error; err != nil {
		return nil, fmt.Errorf("change request not found")
	}
	resp := s.toPCRResponse(r, s.productInfo(tenantID, r.ProductID))
	return &resp, nil
}

// ApproveProductChange applies the proposed MRP onto the product (+ audit
// chip) and closes the request. Role-gated like ApproveStockSetup.
func (s *EnhancedProductService) ApproveProductChange(
	ctx context.Context, id, tenantID, approverID uuid.UUID, approverRole string,
) (*ProductChangeRequestResponse, error) {
	if !s.pcrIsPrivileged(approverRole) {
		return nil, fmt.Errorf("only admin or manager can approve product changes")
	}
	approverName := s.userDisplayName(tenantID, approverID)

	txErr := s.db.Transaction(func(tx *gorm.DB) error {
		var r ProductChangeRequest
		if err := tx.Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
			First(&r).Error; err != nil {
			return fmt.Errorf("change request not found")
		}
		if r.Status != "pending" {
			return fmt.Errorf("request is already %s", r.Status)
		}
		var prod models.Product
		if err := tx.Where("id = ? AND tenant_id = ?", r.ProductID, tenantID).
			First(&prod).Error; err != nil {
			return fmt.Errorf("product not found")
		}
		now := time.Now()
		// v1.0.344 — apply ONLY the fields this request actually proposes, and
		// only the ones not already auto-applied at capture time. A name-only
		// request must never write mrp=0 (proposed_mrp DROP NOT NULL means
		// name-only rows carry 0), so the MRP write is guarded on >0. Idempotent
		// re-applying an already-applied value is harmless.
		updates := map[string]interface{}{}
		if r.ProposedMRP > 0 && r.ProposedMRP != prod.MRP {
			updates["mrp"] = r.ProposedMRP
			updates["last_mrp_change_at"] = now
			updates["last_mrp_change_by_id"] = approverID
			updates["last_mrp_change_by_name"] = approverName
			updates["last_mrp_change_previous"] = prod.MRP
		}
		if pn := strings.TrimSpace(r.ProposedName); pn != "" && !strings.EqualFold(pn, strings.TrimSpace(prod.Name)) {
			updates["name"] = pn
			updates["display_name"] = pn
			// Stale bold range would mis-highlight the new name; clear it.
			updates["display_name_bold_start"] = nil
			updates["display_name_bold_length"] = nil
		}
		if strings.TrimSpace(r.ProposedName) != "" {
			// An approved name is a vouched name — open the purchase name gate.
			updates["name_verified"] = true
		}
		if len(updates) > 0 {
			if err := tx.Model(&models.Product{}).
				Where("id = ? AND tenant_id = ?", r.ProductID, tenantID).
				Updates(updates).Error; err != nil {
				return err
			}
		}
		return tx.Model(&ProductChangeRequest{}).Where("id = ?", r.ID).
			Updates(map[string]interface{}{
				"status":           "approved",
				"approved_by_id":   approverID,
				"approved_by_name": approverName,
				"approved_at":      now,
				"updated_at":       now,
			}).Error
	})
	if txErr != nil {
		return nil, txErr
	}
	return s.GetProductChangeRequest(ctx, id, tenantID)
}

func (s *EnhancedProductService) RejectProductChange(
	ctx context.Context, id, tenantID, rejectorID uuid.UUID, reason string,
) error {
	res := s.db.Model(&ProductChangeRequest{}).
		Where("id = ? AND tenant_id = ? AND status = 'pending' AND deleted_at IS NULL", id, tenantID).
		Updates(map[string]interface{}{
			"status":           "rejected",
			"rejection_reason": reason,
			"approved_by_id":   rejectorID,
			"approved_by_name": s.userDisplayName(tenantID, rejectorID),
			"approved_at":      time.Now(),
			"updated_at":       time.Now(),
		})
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return fmt.Errorf("request not found or already processed")
	}
	return nil
}

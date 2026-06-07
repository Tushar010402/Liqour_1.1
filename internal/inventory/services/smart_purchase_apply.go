package services

import (
	"context"
	"fmt"
	"log"
	"math"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// v1.0.388 — smartPurchaseUpdateStocksEnabled REMOVED. AI apply no longer moves
// stock at submit; stock is moved exactly once in ReceivePurchase (like a normal
// purchase). Keeping a submit-time stock writer double-counted every received
// item (apply +qty AND receive +qty). The SMART_PURCHASE_APPLY_UPDATE_STOCKS env
// flags are now dead.

// smartPurchaseAutoOnboardEnabled gates v1.0.386 authoritative auto-onboard at
// apply: items that matched the catalog but have no shop SKU yet get their
// product CREATED in-transaction instead of being dropped ("no_product"). This
// is the fix for chhotu's 30→27 silent loss. DEFAULT ON — set
// SMART_PURCHASE_AUTO_ONBOARD=0 (or _TENANT_<uuid>=0) to revert to the old
// behaviour (such rows become surfaced blocking skips, still never silent).
func smartPurchaseAutoOnboardEnabled(tenantID uuid.UUID) bool {
	if v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_AUTO_ONBOARD")); v == "0" || strings.EqualFold(v, "false") {
		return false
	}
	if per := strings.TrimSpace(os.Getenv("SMART_PURCHASE_AUTO_ONBOARD_TENANT_" + tenantID.String())); per != "" {
		return !(per == "0" || strings.EqualFold(per, "false"))
	}
	return true
}

// autoOnboardApplyItem creates (or resolves) the shop product for an apply item
// that has no product_id but carries an onboarding payload, dispatching by tier
// to the shared tx-safe core. Returns the resolved product_id, or ("", nil) when
// the payload lacks the minimum data to safely create (name+size) — the caller
// then records a blocking skip (never a silent drop). v1.0.386.
func (s *SmartPurchaseService) autoOnboardApplyItem(tx *gorm.DB, tenantID, shopID uuid.UUID, it SmartPurchaseApplyItem) (string, error) {
	p := it.OnboardingPayload
	if p == nil {
		return "", nil
	}
	sizeML := p.SuggestedSizeML
	if sizeML <= 0 {
		sizeML = it.SizeML
	}
	if sizeML <= 0 {
		sizeML = extractML(it.SizeText)
	}
	cost := it.CostPrice
	if cost <= 0 {
		cost = p.BillCostPrice
	}

	// 1. Master-linked create — master_create_shop_product (high-confidence).
	if strings.TrimSpace(p.MasterSaaSBrandID) != "" {
		sbID, err := uuid.Parse(strings.TrimSpace(p.MasterSaaSBrandID))
		if err != nil {
			return "", fmt.Errorf("bad master_saas_brand_id %q: %w", p.MasterSaaSBrandID, err)
		}
		if sizeML <= 0 {
			return "", nil
		}
		// Pass the payload's size-specific MRP + category as hints (orchestrator
		// already resolved them from brand_variants).
		res, err := ResolveOrCreateShopProductFromMaster(tx, tenantID, shopID, sbID, sizeML, cost, p.MasterMRP, p.MasterCategory)
		if err != nil {
			return "", err
		}
		return res.ProductID.String(), nil
	}

	// 2. matched_other_shop — copy a tenant product's identity into this shop.
	if strings.TrimSpace(p.ExistingProductID) != "" {
		var src models.Product
		if err := tx.Where("tenant_id = ? AND deleted_at IS NULL AND id = ?", tenantID, p.ExistingProductID).
			First(&src).Error; err != nil {
			return "", fmt.Errorf("matched_other_shop source %s not found: %w", p.ExistingProductID, err)
		}
		if sizeML <= 0 {
			sizeML = extractML(src.Size)
		}
		if sizeML <= 0 {
			return "", nil
		}
		if src.SaaSBrandID != nil {
			res, err := ResolveOrCreateShopProductFromMaster(tx, tenantID, shopID, *src.SaaSBrandID, sizeML, cost, src.MRP, "")
			if err != nil {
				return "", err
			}
			return res.ProductID.String(), nil
		}
		res, err := ResolveOrCreateShopProductNew(tx, tenantID, shopID, src.Name, sizeML, "", src.MRP, cost)
		if err != nil {
			return "", err
		}
		return res.ProductID.String(), nil
	}

	// 3. fully_new — create from the suggested name/size (+ any bill MRP/cost).
	name := strings.TrimSpace(p.SuggestedBrandName)
	if name == "" {
		name = strings.TrimSpace(it.BrandName)
	}
	if name == "" || sizeML <= 0 {
		return "", nil // genuinely dataless → blocking skip
	}
	res, err := ResolveOrCreateShopProductNew(tx, tenantID, shopID, name, sizeML, p.MasterCategory, p.MasterMRP, cost)
	if err != nil {
		return "", err
	}
	return res.ProductID.String(), nil
}

// SmartPurchaseApplyItem is one operator-confirmed line in the apply payload.
//
// Flutter sends this after the operator finishes review: their final
// product_id pick + cost + qty + which warnings they confirmed + the AI's
// original guess (so the learning loop can compare AI vs operator).
//
// Field discipline:
//   - Confirmed* fields = what the operator decided (final state).
//   - OriginalAI* fields = what AI guessed (for learning diff).
//   - WasCorrected = true when operator changed any of brand/qty/rate from
//     the AI extraction. Drives the alias-learn / negative-learn / rate-
//     learn gates.
type SmartPurchaseApplyItem struct {
	// Final state (operator-confirmed).
	ProductID         string  `json:"product_id"`
	BrandName         string  `json:"brand_name"`
	SizeText          string  `json:"size_text"`
	SizeML            int     `json:"size_ml"`

	// v1.0.386 — authoritative auto-onboard. When the review item matched the
	// catalog but the shop has no SKU yet, ProductID is empty and these carry
	// what's needed to CREATE the product during apply (inside the tx) so the row
	// is never silently dropped. Echoed from the review item; the client need not
	// pre-create via the onboard chip. See ApplySmartPurchase item loop.
	OnboardingTier    string             `json:"onboarding_tier,omitempty"`    // master_create_shop_product | matched_other_shop | fully_new
	OnboardingPayload *OnboardingPayload `json:"onboarding_payload,omitempty"`
	Cases             int     `json:"cases"`
	Bottles           int     `json:"bottles"`
	QuantityUnit      string  `json:"quantity_unit"` // "cases" | "bottles"
	BottlesPerCase    int     `json:"bottles_per_case"`
	CostPrice         float64 `json:"cost_price"` // per-bottle
	Amount            float64 `json:"amount"`
	BatchNumber       string  `json:"batch_number,omitempty"`
	DutyFee           float64 `json:"duty_fee,omitempty"`

	// AI's original guess (for learning).
	OCRText             string  `json:"ocr_text,omitempty"`              // raw OCR text on the bill row
	OriginalAIBrand     string  `json:"original_ai_brand,omitempty"`     // brand AI extracted before any normalization
	OriginalAIRate      float64 `json:"original_ai_rate,omitempty"`      // rate AI extracted
	OriginalAIQty       int     `json:"original_ai_qty,omitempty"`       // qty AI extracted (in QuantityUnit)
	OriginalProductID   string  `json:"original_product_id,omitempty"`   // AI's first-pick product (negative learning when operator swapped)
	WasCorrected        bool    `json:"was_corrected,omitempty"`         // operator edited brand / qty / rate

	// Operator-confirmed warnings — when the apply gate would block, the
	// operator can include warning kinds here to override.
	UserConfirmedWarnings []string `json:"user_confirmed_warnings,omitempty"`

	// v1.0.221 — shortage / leakage operator input.
	//
	// Bottles is what the bill says was billed. When the physical delivery
	// is short OR bottles broke in transit, operator marks the missing
	// count + reason. Stock only grows by `Bottles - LeakageQty -
	// ShortReceivedQty`. The two int columns map 1:1 to existing
	// stock_purchase_items.leakage and stock_purchase_items.short_received
	// (already in schema).
	//
	// ShortageReason ∈ {"none", "depot_short", "transit_leak",
	// "transit_broken", "other"} — see smart_purchase_shortage.go.
	// ShortageNote is operator-typed free text (only when reason == "other").
	LeakageQty       int    `json:"leakage_qty,omitempty"`
	ShortReceivedQty int    `json:"short_received_qty,omitempty"`
	ShortageReason   string `json:"shortage_reason,omitempty"`
	ShortageNote     string `json:"shortage_note,omitempty"`

	// v1.0.238 — Purcha gate REMOVED. The four purcha_* fields previously
	// here (purcha_confirmed / purcha_qty_observed / purcha_source /
	// purcha_skipped) are gone. AI Purchase now uses Bill+GP reconciliation
	// (BillGPReconciliation on SmartPurchaseResult) instead of a separate
	// Purcha photo upload step.
}

// SmartPurchaseApplyRequest is the operator-confirmed apply payload.
type SmartPurchaseApplyRequest struct {
	JobID         string                   `json:"job_id,omitempty"` // optional — links back to the extraction job
	ShopID        string                   `json:"shop_id"`
	VendorID      string                   `json:"vendor_id,omitempty"`
	InvoiceNumber string                   `json:"invoice_number,omitempty"`
	InvoiceDate   string                   `json:"invoice_date,omitempty"` // YYYY-MM-DD
	Items         []SmartPurchaseApplyItem `json:"items"`
	ReceiptImages []string                 `json:"receipt_images,omitempty"`
	TotalAmount   float64                  `json:"total_amount,omitempty"`
	TaxAmount     float64                  `json:"tax_amount,omitempty"`
	Notes         string                   `json:"notes,omitempty"`

	// Operator-confirmed reconciliation flag kinds (e.g.
	// "subtotal_mismatch") that would otherwise block apply when severity =
	// "block". Without this list, a block-severity flag refuses apply.
	UserConfirmedReconciliations []string `json:"user_confirmed_reconciliations,omitempty"`
}

// SkippedItem is one apply-payload row the backend did NOT record, with a
// human-readable reason. Surfacing these closes the "items silently went
// missing" gap — every row sent to apply is now accounted for (created OR
// reported as skipped), never dropped without a trace.
type SkippedItem struct {
	BrandName string `json:"brand_name"`
	Reason    string `json:"reason"` // no_product | bad_product_id | zero_bottles | onboard_failed | onboard_insufficient_data
	// v1.0.386 — Blocking marks a row the operator MUST address (it carried an
	// onboarding intent we couldn't auto-fulfil), vs an informational skip. The
	// client should hard-surface these so nothing is quietly lost.
	Blocking bool `json:"blocking,omitempty"`
}

// SmartPurchaseApplyResponse is what Flutter gets back after a successful apply.
type SmartPurchaseApplyResponse struct {
	PurchaseID      string `json:"purchase_id"`
	PurchaseNumber  string `json:"purchase_number"`
	ItemsCreated    int    `json:"items_created"`
	// v1.0.386 — how many of ItemsCreated were products auto-onboarded in-tx (no
	// shop SKU existed). Drives the "N products auto-created from catalogue"
	// post-apply summary so the operator sees it happened (transparency).
	AutoCreatedCount int   `json:"auto_created_count"`
	ItemsLearned    int    `json:"items_learned"`     // alias hits + neg hits + rate hits
	NewVendorID     string `json:"new_vendor_id,omitempty"` // when caller asked us to also auto-create
	// Rows that were sent to apply but NOT recorded, each with a reason.
	// Lets the client tell the operator "recorded X, skipped Y (why)".
	SkippedItems    []SkippedItem `json:"skipped_items,omitempty"`
	SkippedCount    int           `json:"skipped_count"`
}

// ApplySmartPurchase creates the stock_purchase + items + capture learning.
//
// 100% rule (v1.0.193): refuse apply when any item has unconfirmed
// `block`-severity warnings (close-misread, quantity_disputed, subtotal
// mismatch > 5%). Operator must explicitly include the warning kind in
// `user_confirmed_warnings` (or `user_confirmed_reconciliations` for
// document-level flags) before we'll write the purchase.
func (s *SmartPurchaseService) ApplySmartPurchase(
	ctx context.Context,
	tenantID, userID uuid.UUID,
	req SmartPurchaseApplyRequest,
) (*SmartPurchaseApplyResponse, error) {

	if len(req.Items) == 0 {
		return nil, fmt.Errorf("no items to apply")
	}
	shopID, err := uuid.Parse(req.ShopID)
	if err != nil {
		return nil, fmt.Errorf("invalid shop_id: %w", err)
	}

	// v1.0.217 Track 8 — receipt dedup. Refuse to create a second
	// stock_purchase for the same (invoice_number, vendor_id, shop_id)
	// within the past 7 days. Prevents accidental double-submit (operator
	// loses connection, re-taps Submit). Returns a structured "duplicate"
	// error the handler maps to 409 Conflict.
	if strings.TrimSpace(req.InvoiceNumber) != "" {
		var existing models.StockPurchase
		// v1.0.389 — exclude cancelled/rejected purchases from the dedup check.
		// A cancelled receipt (e.g. one reverted for a clean re-submit) must NOT
		// block re-applying the same invoice — otherwise the operator is stuck on
		// "Already submitted / duplicate_receipt" with no way to resubmit (chhotu).
		dupErr := s.db.Where(`
			tenant_id = ? AND shop_id = ? AND receipt_no = ?
			AND created_at >= NOW() - INTERVAL '7 days'
			AND deleted_at IS NULL
			AND COALESCE(status, '') NOT IN ('cancelled', 'rejected')
		`, tenantID, shopID, strings.TrimSpace(req.InvoiceNumber)).
			Order("created_at DESC").First(&existing).Error
		if dupErr == nil && existing.ID != uuid.Nil {
			return nil, fmt.Errorf("duplicate_receipt: invoice %s already applied at this shop on %s as purchase %s",
				req.InvoiceNumber,
				existing.PurchaseDate.Format("2006-01-02"),
				existing.PurchaseNumber)
		}
	}
	var vendorID uuid.UUID
	if req.VendorID != "" {
		v, err := uuid.Parse(req.VendorID)
		if err != nil {
			return nil, fmt.Errorf("invalid vendor_id: %w", err)
		}
		vendorID = v
	}

	// PURCHASE IMAGE GATE (2026-05-18; strict front+back v1.0.338) — block before
	// any rows are written, mirroring the name gate in purchase_service.go.
	//
	// Two modes:
	//   • legacy (default): only products created by AI Stock Setup
	//     (created_via='stock_setup') with NO photo at all are gated — strictly
	//     forward-only, zero disruption to pre-existing data.
	//   • strict (PURCHASE_REQUIRE_FRONT_BACK=1): EVERY matched product must have
	//     BOTH a front and a back photo before purchase records stock against it.
	//     The response says which face each product still needs so the app can
	//     drive the front+back capture flow inline, then resubmit.
	//
	// Run pre-tx on s.db so the early return needs no rollback.
	{
		ids := make([]uuid.UUID, 0, len(req.Items))
		for _, it := range req.Items {
			if it.ProductID == "" {
				continue
			}
			if pid, perr := uuid.Parse(it.ProductID); perr == nil {
				ids = append(ids, pid)
			}
		}
		if len(ids) > 0 {
			strict := os.Getenv("PURCHASE_REQUIRE_FRONT_BACK") == "1"
			if strict {
				// Fetch the face URLs + name_verified so we can report exactly
				// what's missing.
				type prodFaces struct {
					ID           uuid.UUID `gorm:"column:id"`
					Name         string    `gorm:"column:name"`
					Front        string    `gorm:"column:front_image_url"`
					Back         string    `gorm:"column:back_image_url"`
					NameVerified bool      `gorm:"column:name_verified"`
				}
				var rows []prodFaces
				// v1.0.344 — forward-only scope. Only AI-created products
				// (stock_setup / ai_purchase) are gated; legacy products stay
				// exempt, matching the home Purchase Entry button precondition
				// (GET /products/photo-status). Keeps the submit-time gate and the
				// pre-purchase gate identical so nothing surprises the operator.
				// v1.0.356 — also block products that have photos but an UNVERIFIED
				// name (when PURCHASE_REQUIRE_NAME_VERIFIED on, default), so a
				// low-confidence/garbled identity can never enter a purchase. The
				// precondition gate counts these too, so this is the backstop.
				requireNameVerified := os.Getenv("PURCHASE_REQUIRE_NAME_VERIFIED") != "0"
				// v1.0.357 — BACK image is OPTIONAL (front + verified name suffice for
				// correct item consideration; back only carries MRP). A product without a
				// back image is NOT blocked. Set PURCHASE_REQUIRE_BACK_IMAGE=1 to re-require.
				requireBack := os.Getenv("PURCHASE_REQUIRE_BACK_IMAGE") == "1"
				where := `tenant_id = ? AND id IN ? AND deleted_at IS NULL
				        AND created_via IN ('stock_setup','ai_purchase')
				        AND (COALESCE(front_image_url,'') = ''`
				if requireBack {
					where += ` OR COALESCE(back_image_url,'') = ''`
				}
				if requireNameVerified {
					where += ` OR name_verified = false`
				}
				where += `)`
				if scErr := s.db.Table("products").
					Select("id, name, front_image_url, back_image_url, name_verified").
					Where(where, tenantID, ids).
					Scan(&rows).Error; scErr == nil && len(rows) > 0 {
					need := make([]ImageRequiredProduct, 0, len(rows))
					for _, r := range rows {
						mf := strings.TrimSpace(r.Front) == ""
						mb := strings.TrimSpace(r.Back) == ""
						need = append(need, ImageRequiredProduct{
							ID:             r.ID,
							Name:           r.Name,
							MissingFront:   mf,
							MissingBack:    requireBack && mb, // don't ask for an optional back
							UnverifiedName: requireNameVerified && !r.NameVerified && !mf,
						})
					}
					return nil, &PurchaseImageRequiredError{Products: need}
				}
			} else {
				var need []ImageRequiredProduct
				if scErr := s.db.Table("products").
					Select("id, name").
					Where(`tenant_id = ? AND id IN ? AND deleted_at IS NULL
					        AND created_via = ?
					        AND COALESCE(image_url,'') = ''
					        AND COALESCE(front_image_url,'') = ''
					        AND COALESCE(back_image_url,'') = ''`,
						tenantID, ids, "stock_setup").
					Scan(&need).Error; scErr == nil && len(need) > 0 {
					return nil, &PurchaseImageRequiredError{Products: need}
				}
			}
		}
	}

	// Build models.StockPurchase directly. The legacy CreatePurchase service
	// in purchase_service.go takes a different request shape (pre-AI), so
	// we build the row inline to avoid an awkward request adapter.
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
			panic(r)
		}
	}()

	// Generate a purchase number — same shape as legacy: PUR-YYYYMMDD-NNNN.
	purchaseNo, err := s.generateSmartPurchaseNumber(tx, tenantID)
	if err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("generate purchase number: %w", err)
	}

	purchaseDate := time.Now()
	if req.InvoiceDate != "" {
		if d, err := time.Parse("2006-01-02", req.InvoiceDate); err == nil {
			purchaseDate = d
		}
	}

	purchase := models.StockPurchase{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		PurchaseNumber: purchaseNo,
		VendorID:       vendorID,
		ShopID:         shopID,
		PurchaseDate:   purchaseDate,
		Status:         "pending",
		Notes:          req.Notes,
		ReceiptNo:      req.InvoiceNumber,
		ReceiptImages:  models.JSONStringList(req.ReceiptImages),
		CreatedBy:      userID,
		TotalAmount:    req.TotalAmount,
	}
	if err := tx.Create(&purchase).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("create purchase: %w", err)
	}

	itemsCreated := 0
	// v1.0.353 — account for every row. A row sent to apply is either
	// recorded or reported back as skipped (with reason); nothing is dropped
	// silently. The client surfaces these so the operator can fix/add them.
	skipped := make([]SkippedItem, 0)
	autoOnboarded := 0 // v1.0.386 — products created in-tx so the row could save
	skipBlk := func(it SmartPurchaseApplyItem, reason string, blocking bool) {
		name := strings.TrimSpace(it.BrandName)
		if name == "" {
			name = strings.TrimSpace(it.OCRText)
		}
		log.Printf("[SmartPurchase v353] skipped row %q reason=%s blocking=%v", name, reason, blocking)
		skipped = append(skipped, SkippedItem{BrandName: name, Reason: reason, Blocking: blocking})
	}
	skip := func(it SmartPurchaseApplyItem, reason string) { skipBlk(it, reason, false) }
	autoOnboard := smartPurchaseAutoOnboardEnabled(tenantID)
	for _, it := range req.Items {
		// v1.0.386 — AUTHORITATIVE AUTO-ONBOARD. An item with no product_id that
		// matched the catalog (carries an onboarding tier + payload) is CREATED
		// here, in this transaction, so it is never silently dropped (chhotu's
		// 30→27). Idempotent: two same brand+size rows resolve to one product and
		// the stock upsert below sums their quantities. Only genuinely dataless
		// rows become a BLOCKING skip (surfaced, never silent); the rest commit.
		if it.ProductID == "" {
			if !autoOnboard || it.OnboardingPayload == nil {
				skipBlk(it, "no_product", true)
				continue
			}
			newPID, oerr := s.autoOnboardApplyItem(tx, tenantID, shopID, it)
			if oerr != nil {
				// Don't roll back the whole purchase for one row — surface it.
				log.Printf("[SmartPurchase v386] auto-onboard failed for %q: %v", strings.TrimSpace(it.BrandName), oerr)
				skipBlk(it, "onboard_failed", true)
				continue
			}
			if newPID == "" {
				skipBlk(it, "onboard_insufficient_data", true)
				continue
			}
			it.ProductID = newPID
			autoOnboarded++
		}
		productID, err := uuid.Parse(it.ProductID)
		if err != nil {
			skip(it, "bad_product_id")
			continue
		}
		bottles := it.Bottles
		if bottles == 0 && it.BottlesPerCase > 0 && it.Cases > 0 {
			bottles = it.Cases * it.BottlesPerCase
		}
		if bottles <= 0 {
			skip(it, "zero_bottles")
			continue
		}

		// v1.0.390 — shortage / leakage. Store GROSS billed bottles as the item
		// Quantity (identical to the legacy CreatePurchase path) and keep the raw
		// Leakage/ShortReceived alongside. The single subtraction
		// `net = quantity - leakage - short` happens exactly ONCE, later, in
		// ReceivePurchase. The previous code stored the already-netted
		// actualReceived here AND also persisted Leakage/ShortReceived, so
		// ReceivePurchase subtracted them a SECOND time → stock landed at
		// `bottles - 2*(short+leak)`. Storing gross also keeps bill-line display
		// + exports correct (they render item.Quantity as the billed count).
		// resolveShortage is now used only to reject impossible client input
		// (negative net); on validation failure we DROP the shortage (treat as a
		// full receipt) rather than persist a bogus value.
		leakageQty := it.LeakageQty
		shortQty := it.ShortReceivedQty
		if leakageQty > 0 || shortQty > 0 {
			res := resolveShortage(bottles, bottles, bottles-leakageQty-shortQty, it.ShortageReason, it.ShortageNote)
			if !res.IsValid {
				log.Printf("⚠️ [SmartPurchase] shortage validation failed for product %s: %s — ignoring shortage, using billed bottles",
					productID, res.ValidationError)
				leakageQty, shortQty = 0, 0
			} else {
				log.Printf("[SmartPurchase v390] shortage recorded for %s: %s (gross %d, net into stock %d)",
					productID, res.AuditNote, bottles, res.ActualReceivedQty)
			}
		}

		spi := models.StockPurchaseItem{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantID,
			},
			StockPurchaseID: purchase.ID,
			ProductID:       productID,
			Quantity:        bottles,
			UnitCost:        it.CostPrice,
			TotalCost:       it.Amount,
			BatchNumber:     it.BatchNumber,
			DutyFee:         it.DutyFee,
			Leakage:         leakageQty,
			ShortReceived:   shortQty,
		}
		if err := tx.Create(&spi).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("create purchase item: %w", err)
		}
		itemsCreated++

		// v1.0.388 — STOCK IS NO LONGER MOVED HERE. AI apply only creates the
		// `pending` purchase + items (+ qty-0 stock rows for auto-onboarded SKUs).
		// ALL stock movement happens exactly once, later, in ReceivePurchase —
		// identical to a normal (non-AI) purchase. Previously apply incremented
		// stock at submit AND receive incremented again → every item double-counted
		// (chhotu: 90ml Royal Stag opening 8 + 96 should be 104, but showed 200 =
		// 8+96+96). The item row above stores GROSS bottles; the single
		// shortage/leakage subtraction happens in ReceivePurchase.

		// v1.0.221 — self-aligning catalog. When GP-primary pipeline is on
		// for this tenant, promote tenant.products.name to GP canonical and
		// capture the bill OCR text as a shop-scoped alias for next time.
		// Hygiene guards inside both helpers reject pollution attempts.
		gpOnlyApply := gpOnlyNamesEnabled(userID.String())
		if gpPrimaryEnabled(tenantID) || gpOnlyApply {
			// v1.0.359 — the canonical promoted into products.name MUST be the
			// GATE PASS name, never the bill OCR text (promoting bill text was the
			// poison: it overwrote the product name with the short invoice string).
			// Under GP-only the review screen's BrandName already IS the GP name
			// (the operator submits back what they saw), so promote that. The bill
			// text stays an ALIAS KEY only (bill→canonical), which is correct.
			var canonical string
			if gpOnlyApply {
				canonical = strings.TrimSpace(it.BrandName) // GP name (post-v359)
			} else {
				canonical = strings.TrimSpace(it.OCRText)
				if canonical == "" {
					canonical = strings.TrimSpace(it.BrandName)
				}
			}
			if canonical != "" && !strings.EqualFold(canonical, "Unread — needs review") {
				if _, _, changed, perr := s.promoteCanonicalName(tx, tenantID, productID, canonical); perr != nil {
					log.Printf("[SmartPurchase v221] promoteCanonicalName failed for %s: %v", productID, perr)
				} else if changed {
					log.Printf("[SmartPurchase v221] canonical promoted for %s → %q", productID, canonical)
				}
			}
			// Bill OCR text → canonical alias (direction is correct: teaches the
			// matcher "this bill string means this product"). Prefer the raw AI
			// brand, fall back to the bill OCR text.
			billKey := strings.TrimSpace(it.OriginalAIBrand)
			if billKey == "" {
				billKey = strings.TrimSpace(it.OCRText)
			}
			if billKey != "" && canonical != "" && !strings.EqualFold(billKey, canonical) {
				if aerr := captureBillAliasFromGPMatch(s.aliasService, tenantID, shopID, productID, billKey, canonical); aerr != nil {
					log.Printf("[SmartPurchase v221] alias capture failed: %v", aerr)
				}
			}
		}
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("commit purchase: %w", err)
	}

	// Capture learning AFTER successful commit. Async — don't block the
	// apply response. Each callee uses ON CONFLICT upserts so re-fires are
	// safe.
	go s.captureSmartPurchaseLearning(tenantID, userID, shopID, req.Items, "applied")

	// v1.0.238 Track C — training-corpus capture. Async, env-gated, idempotent.
	// Replaces (and broadens) the Purcha gate's correctness signal with a
	// per-row (ai_raw, truth) pair for future cv-sidecar CNN training.
	var jobIDForCapture uuid.UUID
	if req.JobID != "" {
		if parsed, perr := uuid.Parse(req.JobID); perr == nil {
			jobIDForCapture = parsed
		}
	}
	s.capturePurchaseTrainingSamples(tenantID, shopID, jobIDForCapture, purchase.ID, req, "apply_success")

	return &SmartPurchaseApplyResponse{
		PurchaseID:       purchase.ID.String(),
		PurchaseNumber:   purchase.PurchaseNumber,
		ItemsCreated:     itemsCreated,
		AutoCreatedCount: autoOnboarded,
		SkippedItems:     skipped,
		SkippedCount:     len(skipped),
	}, nil
}

// generateSmartPurchaseNumber produces a PUR-YYYYMMDD-NNNN format string,
// scoped per-tenant per-day. Mirrors the legacy purchase_service.go counter.
func (s *SmartPurchaseService) generateSmartPurchaseNumber(tx *gorm.DB, tenantID uuid.UUID) (string, error) {
	today := time.Now().Format("20060102")
	prefix := fmt.Sprintf("PUR-%s-", today)
	var maxNo int64
	row := tx.Raw(`
		SELECT COALESCE(MAX(
		    CASE WHEN purchase_number LIKE ? THEN
		        CAST(SUBSTRING(purchase_number FROM ?) AS INTEGER)
		    ELSE 0 END
		), 0)
		FROM stock_purchases
		WHERE tenant_id = ? AND deleted_at IS NULL
	`, prefix+"%", len(prefix)+1, tenantID).Row()
	_ = row.Scan(&maxNo)
	return fmt.Sprintf("%s%04d", prefix, maxNo+1), nil
}

// captureSmartPurchaseLearning is the v1.0.193 purchase analog of Smart
// Sale's captureApplyLearning — the SINGLE point where every operator edit
// on the review screen becomes training signal.
//
// Three independent goroutines so a slow path doesn't block the others:
//   (a) alias learning  — positive (operator-confirmed pick) + negative
//       (operator swapped away from AI's #1) into ocr_brand_aliases /
//       ocr_negative_aliases.
//   (b) rate learning   — per-shop cost-price into shop_product_rates.
//   (c) digit corrections — when AI's qty / rate / brand-text differ from
//       the operator's final value, capture into ocr_digit_corrections so
//       the next extraction's prompt prefers the corrected reading.
//
// Idempotent (every callee uses ON CONFLICT upserts). Hygiene guards in
// LearnAliasScoped (jaccard ≥ 0.20, length ≥ 2, alias≠canonical, negative-
// table block) prevent dirty entries.
func (s *SmartPurchaseService) captureSmartPurchaseLearning(
	tenantID, userID, shopID uuid.UUID,
	items []SmartPurchaseApplyItem,
	applyOutcome string,
) {
	if len(items) == 0 {
		return
	}

	// (a) Alias learning — positive + negative.
	if s.aliasService != nil {
		go func() {
			defer func() {
				if r := recover(); r != nil {
					log.Printf("SmartPurchase: captureLearning(alias) panic recovered: %v (outcome=%s)", r, applyOutcome)
				}
			}()
			aliasHits, negHits := 0, 0
			for _, it := range items {
				// Same relaxed gate as Smart Sale v1.0.163 — also learn
				// when the operator just CONFIRMED a row whose OCR text
				// differs from the matched product's brand name. That's
				// equally valid signal that "this OCR text IS this brand".
				ocrKey := strings.TrimSpace(it.OCRText)
				if ocrKey == "" {
					ocrKey = strings.TrimSpace(it.OriginalAIBrand)
				}
				if ocrKey == "" {
					ocrKey = strings.TrimSpace(it.BrandName)
				}
				if ocrKey == "" || it.ProductID == "" {
					continue
				}
				productID, err := uuid.Parse(it.ProductID)
				if err != nil {
					continue
				}

				learnFromConfirmation := !it.WasCorrected &&
					ocrKey != "" &&
					!strings.EqualFold(ocrKey, strings.TrimSpace(it.BrandName))
				if !it.WasCorrected && !learnFromConfirmation {
					continue
				}

				// Negative alias: when operator picked a DIFFERENT product
				// than AI's first guess, mark AI's guess as "rejected at
				// this shop for this OCR text".
				if it.OriginalProductID != "" && it.OriginalProductID != it.ProductID {
					if rejectedPID, perr := uuid.Parse(it.OriginalProductID); perr == nil {
						if naErr := s.aliasService.LearnNegativeAliasScoped(tenantID, shopID, ocrKey, rejectedPID); naErr == nil {
							negHits++
							log.Printf("SmartPurchase learning(%s): NEG '%s' rejected → %s (shop=%s)",
								applyOutcome, ocrKey, it.OriginalProductID, shopID)
						}
					}
				}

				// Positive alias: pull canonical name from products table.
				var product models.Product
				if err := s.db.Select("name").Where("id = ?", productID).First(&product).Error; err == nil {
					if laErr := s.aliasService.LearnAliasScoped(tenantID, shopID, ocrKey, product.Name, &productID, "smart_purchase"); laErr == nil {
						aliasHits++
						log.Printf("SmartPurchase learning(%s): LEARNED '%s' → '%s' (shop=%s)",
							applyOutcome, ocrKey, product.Name, shopID)
					}
					// v1.0.199 — DUAL-WRITE tenant-wide so sibling shops in the
					// same tenant inherit the OCR→product mapping.
					if shopID != uuid.Nil {
						if laErr := s.aliasService.LearnAliasScoped(tenantID, uuid.Nil, ocrKey, product.Name, &productID, "smart_purchase_tenant"); laErr == nil {
							log.Printf("SmartPurchase learning(%s): LEARNED tenant-wide '%s' → '%s'",
								applyOutcome, ocrKey, product.Name)
						}
					}
				}
			}
			log.Printf("SmartPurchase: captureLearning(alias) done — outcome=%s alias_hits=%d neg_hits=%d items=%d",
				applyOutcome, aliasHits, negHits, len(items))
		}()
	}

	// (b) Per-shop rate learning. Same write contract as Smart Sale's
	// shop_product_rates (one table, two write sources). Rate is the
	// per-bottle cost from the bill (not MRP — purchase rates ≠ sale
	// rates). source field distinguishes purchase vs sale.
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("SmartPurchase: captureLearning(rate) panic recovered: %v (outcome=%s)", r, applyOutcome)
			}
		}()
		rateHits := 0
		for _, it := range items {
			if it.ProductID == "" || it.CostPrice <= 0 {
				continue
			}
			pid, err := uuid.Parse(it.ProductID)
			if err != nil {
				continue
			}
			// Skip when within ₹0.5 of the original AI rate AND not corrected
			// — that's a no-op confirmation, no new info.
			if !it.WasCorrected && math.Abs(it.CostPrice-it.OriginalAIRate) <= 0.5 {
				continue
			}
			source := "smart_purchase_confirmation"
			if it.WasCorrected {
				source = "smart_purchase_correction"
			}
			upsertSQL := `
				INSERT INTO shop_product_rates
					(tenant_id, shop_id, product_id, last_user_rate, last_corrected_at, last_corrected_by_id, occurrence_count, source)
				VALUES (?, ?, ?, ?, NOW(), ?, 1, ?)
				ON CONFLICT (tenant_id, shop_id, product_id) DO UPDATE
				SET last_user_rate = EXCLUDED.last_user_rate,
				    last_corrected_at = NOW(),
				    last_corrected_by_id = EXCLUDED.last_corrected_by_id,
				    occurrence_count = shop_product_rates.occurrence_count + 1,
				    source = EXCLUDED.source,
				    updated_at = NOW()
			`
			if err := s.db.Exec(upsertSQL, tenantID, shopID, pid, it.CostPrice, userID, source).Error; err != nil {
				log.Printf("SmartPurchase: shop_product_rates upsert failed for %s: %v", pid, err)
				continue
			}
			rateHits++
			log.Printf("SmartPurchase learning(%s): LEARNED shop_rate %s @ shop %s = ₹%.2f (was ₹%.2f, source=%s)",
				applyOutcome, pid, shopID, it.CostPrice, it.OriginalAIRate, source)
		}
		log.Printf("SmartPurchase: captureLearning(rate) done — outcome=%s rate_hits=%d", applyOutcome, rateHits)
	}()

	// (c) Digit-correction capture. When the operator's final qty / rate /
	// brand text differs at the character level from AI's extraction,
	// capture into ocr_digit_corrections. The extractor prompt picks the
	// top corrections per shop on the next run (LoadTopDigitConfusions in
	// digit_correction_capture.go).
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("SmartPurchase: captureLearning(digits) panic recovered: %v (outcome=%s)", r, applyOutcome)
			}
		}()
		digitHits := 0
		for _, it := range items {
			if !it.WasCorrected {
				continue
			}
			// Qty correction.
			if it.OriginalAIQty > 0 && it.Cases > 0 && it.OriginalAIQty != it.Cases {
				captureDigitCorrection(s.db.DB, tenantID, shopID, "purchase_qty",
					fmt.Sprintf("%d", it.OriginalAIQty),
					fmt.Sprintf("%d", it.Cases))
				digitHits++
			}
			// Rate correction.
			if it.OriginalAIRate > 0 && it.CostPrice > 0 &&
				math.Abs(it.OriginalAIRate-it.CostPrice) > 0.5 {
				captureDigitCorrection(s.db.DB, tenantID, shopID, "purchase_rate",
					fmt.Sprintf("%.2f", it.OriginalAIRate),
					fmt.Sprintf("%.2f", it.CostPrice))
				digitHits++
			}
			// Brand text correction (operator typed a fix that differs from
			// AI's read at the character level).
			if it.OriginalAIBrand != "" && it.BrandName != "" &&
				!strings.EqualFold(strings.TrimSpace(it.OriginalAIBrand), strings.TrimSpace(it.BrandName)) {
				captureDigitCorrection(s.db.DB, tenantID, shopID, "purchase_brand",
					it.OriginalAIBrand, it.BrandName)
				digitHits++
			}
		}
		log.Printf("SmartPurchase: captureLearning(digits) done — outcome=%s digit_hits=%d", applyOutcome, digitHits)
	}()
}

// captureDigitCorrection writes a single ocr_digit_corrections row.
// Idempotent ON CONFLICT upsert. Mirrors the helper used in Smart Sale +
// Stock Setup; kept inline here so we don't add a circular import on the
// inventory<->sales<->stocksetup digit-correction service refactor that's
// out of scope for v1.0.193.
func captureDigitCorrection(db *gorm.DB, tenantID, shopID uuid.UUID, field, raw, corrected string) {
	raw = strings.TrimSpace(raw)
	corrected = strings.TrimSpace(corrected)
	if raw == "" || corrected == "" || raw == corrected {
		return
	}
	upsertSQL := `
		INSERT INTO ocr_digit_corrections
			(tenant_id, shop_id, source, field, raw_value, corrected_value, occurrence_count, last_corrected_at)
		VALUES (?, ?, 'smart_purchase', ?, ?, ?, 1, NOW())
		ON CONFLICT (tenant_id, shop_id, source, field, raw_value, corrected_value) DO UPDATE
		SET occurrence_count = ocr_digit_corrections.occurrence_count + 1,
		    last_corrected_at = NOW(),
		    updated_at = NOW()
	`
	if err := db.Exec(upsertSQL, tenantID, shopID, field, raw, corrected).Error; err != nil {
		log.Printf("SmartPurchase: ocr_digit_corrections upsert failed (%s/%s→%s): %v", field, raw, corrected, err)
	}
}

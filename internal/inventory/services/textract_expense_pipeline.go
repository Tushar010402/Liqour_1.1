package services

import (
	"context"
	"fmt"
	"log"
	"math"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/textract"
	ttypes "github.com/aws/aws-sdk-go-v2/service/textract/types"
	"github.com/google/uuid"
	"golang.org/x/sync/errgroup"
)

// v1.0.199 — Textract AnalyzeExpense primary pipeline.
//
// Why a separate file from textract_purchase_pipeline.go:
//
// AnalyzeDocument(TABLES) treats an invoice like a generic gridded document
// and gives back row/col cell geometry. That works on Smart Sale's
// handwritten daily-sale registers (one number per cell, no semantic ambiguity)
// but fails on real liquor invoices where a single visual cell carries
// "5 Cs." stacked on "(60 Pcs)". TABLES either splits those into two rows
// (losing association) or merges them as garbled text.
//
// AnalyzeExpense is purpose-built for invoices/receipts. It returns
// LineItemFields tagged with semantic types (ITEM, QUANTITY, UNIT_PRICE,
// PRICE) and SummaryFields (VENDOR_NAME, INVOICE_RECEIPT_ID,
// INVOICE_RECEIPT_DATE, SUBTOTAL, TAX, TOTAL) — at $0.008/page vs $0.10/page
// for AnalyzeDocument(TABLES).
//
// Real-data on chhotu's SONU SINGH FL-2 invoice:
//   AnalyzeDocument(TABLES) = 0/44 rows
//   AnalyzeExpense          = expected to match LineItemFields semantically
//
// This file is the primary Phase A entry point. The legacy TABLES path
// (textract_purchase_pipeline.go) stays as the per-page secondary; LLM
// cascade as the rare last-resort fallback.

// stockPurchaseAnalyzerForTenant chooses the Textract feature for this tenant.
//
// Order of precedence:
//   STOCK_PURCHASE_ANALYZER (global)              — "expense" | "tables" | "llm"
//   STOCK_PURCHASE_ANALYZER_TENANT_<uuid>         — same values, per-tenant override
//   STOCK_PURCHASE_PIPELINE / _TENANT_<uuid>      — kill-switch: "disabled" / "off" / "0" / "gemini" / "openai" / "claude" / "llm"
//                                                   (preserved from v1.0.169)
//
// Default is "expense" once Phase F passes; until then, we ship as opt-in
// via STOCK_PURCHASE_ANALYZER_TENANT_<chhotu>=expense so production runs
// keep falling through to the existing TABLES path on other tenants.
func stockPurchaseAnalyzerForTenant(tenantID uuid.UUID) string {
	// First honor the existing kill-switch — if PIPELINE says disabled / llm,
	// don't even try Textract at all.
	if !textractPurchasePipelineEnabledForTenant(tenantID) {
		return "llm"
	}
	per := strings.ToLower(strings.TrimSpace(
		envOrEmpty("STOCK_PURCHASE_ANALYZER_TENANT_" + tenantID.String())))
	if per != "" {
		return normalizeAnalyzerName(per)
	}
	global := strings.ToLower(strings.TrimSpace(envOrEmpty("STOCK_PURCHASE_ANALYZER")))
	if global != "" {
		return normalizeAnalyzerName(global)
	}
	return "expense"
}

func normalizeAnalyzerName(s string) string {
	switch s {
	case "expense", "analyze_expense", "ax":
		return "expense"
	case "tables", "table", "analyze_document", "tx":
		return "tables"
	case "llm", "gemini", "claude", "openai":
		return "llm"
	}
	return "expense"
}

// envOrEmpty mirrors os.Getenv. Aliased so future tests can swap behavior
// without touching every call-site here.
func envOrEmpty(key string) string { return os.Getenv(key) }

// textractPageConcurrency is the max number of Textract pages processed
// concurrently across the bill (AnalyzeExpense) and gate-pass (AnalyzeDocument
// TABLES) pipelines. v1.0.340.
//
// Default 2 matches the AWS Textract synchronous TPS quota (~2/account in
// ap-south-1; the TransactionsPerSecondLimit on AnalyzeExpense/AnalyzeDocument).
// At that quota the extraction is ALREADY fully parallel for chhotu's 2-page
// docs, so the per-job ~3 min is dominated by Textract's own per-call latency,
// not by app-side serialization. Raising this knob ONLY helps after an AWS
// Service Quotas increase for those TPS limits — without that, the extra
// in-flight calls just hit ProvisionedThroughputExceededException and the
// retry-with-backoff makes the job SLOWER, not faster. Exposed as a knob so the
// app side can be turned up in lockstep with the AWS quota bump, no redeploy.
// Clamped to [1, 8].
func textractPageConcurrency() int {
	if v := strings.TrimSpace(os.Getenv("STOCK_PURCHASE_TEXTRACT_CONCURRENCY")); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 1 && n <= 8 {
			return n
		}
	}
	return 2
}

// expenseHeader carries the SummaryFields lifted off an AnalyzeExpense
// response. The orchestrator (smart_purchase_service.go) populates the
// existing local vars at lines ~85-90 from this struct so downstream
// matching/reconciliation behaves identically whether the header came
// from Textract Expense, Textract Queries, or the LLM fallback.
type expenseHeader struct {
	VendorName    string
	VendorGST     string
	VendorAddress string
	InvoiceNumber string
	InvoiceDate   string
	SubTotal      float64
	TaxAmount     float64
	TotalAmount   float64
	// FieldConfidence keyed by tag — same shape as ExtractedPurchaseItem
	// so Flutter chips can render a uniform UX for header + line items.
	FieldConfidence map[string]float64
}

// expenseResult is the Phase-A primary output. Items + header + which method
// produced each page so the orchestrator can blend with TABLES/LLM fallback
// outputs and propagate analyze_method to Flutter.
type expenseResult struct {
	Items         []ExtractedPurchaseItem
	Header        expenseHeader
	PageMethods   []string // one per request page: "expense" | "tables" | "queries" | "llm"
	AnalyzeMethod string   // submission-level rollup (see SmartPurchaseResult.AnalyzeMethod)
	NeedsTables   []int    // page indices (0-based) that did NOT yield enough rows from Expense alone
	NeedsLLM      []int    // page indices that failed both Expense and TABLES
}

// extractWithAnalyzeExpense is the Phase-A entry point. Calls AnalyzeExpense
// per page in parallel (errgroup, SetLimit(8)), maps LineItemFields to
// ExtractedPurchaseItem rows, lifts SummaryFields into the header, and
// returns per-page method tags so the caller can run the TABLES fallback
// only on the pages that came back partial.
func extractWithAnalyzeExpense(
	ctx context.Context,
	req *SmartPurchaseRequest,
	tenantID, shopID uuid.UUID,
) (*expenseResult, error) {
	_ = shopID // reserved for the alias-cascade pre-matcher (Phase A4 future)

	client, err := newTextractPurchaseClient(ctx)
	if err != nil {
		return nil, err
	}

	startedAt := time.Now()
	pageCount := len(req.Images)
	if pageCount == 0 {
		return &expenseResult{}, nil
	}

	type perPage struct {
		idx     int
		items   []ExtractedPurchaseItem
		header  expenseHeader
		method  string
		needsTx bool // true = escalate this page to TABLES
		needsLM bool // true = escalate this page to LLM (after TABLES too)
	}
	pages := make([]perPage, pageCount)

	// AWS Textract sync TPS in ap-south-1 is ~2 per account by default
	// (TransactionsPerSecondLimit on AnalyzeExpense). SetLimit(2) avoids
	// ProvisionedThroughputExceededException. The retry-with-backoff in
	// cachedAnalyzeExpense handles transient bursts when TPS does spike.
	g, gctx := errgroup.WithContext(ctx)
	g.SetLimit(textractPageConcurrency())

	deskew := newDeskewClient()

	for i, img := range req.Images {
		i := i
		img := img
		if len(img.Data) == 0 {
			pages[i] = perPage{idx: i, needsTx: false, needsLM: true, method: "skip"}
			continue
		}
		g.Go(func() error {
			// v1.0.215.4 — DUAL-VARIANT EXPENSE, parallel within a page.
			// Variant A (Catmull-Rom q=92 + deskew) — canonical baseline.
			// Variant B (BiLinear q=80, no deskew) — different segmentation,
			//   recovers middle rows variant A drops (real-data: +5 on chhotu).
			// Variant C (bottom-60% crop) — gated behind STOCK_PURCHASE_VARIANT_C=1
			//   (default off; real-data showed it adds 0 rows on chhotu's bill).
			//
			// v215.4 parallelizes A and B within each page's goroutine to keep
			// total OCR latency at ~13s (was ~25s in v215.1 with sequential
			// variants). Cost: 2 concurrent AnalyzeExpense calls per page,
			// up to 4 in flight across 2 parallel pages — Textract sync TPS
			// retry-with-backoff in cachedAnalyzeExpense absorbs the throttle.
			preA := prepareTextractImageVariant(img.Data, 0)
			preB := prepareTextractImageVariant(img.Data, 1)
			dctx, dcancel := context.WithTimeout(gctx, 3*time.Second)
			deskA := deskew.Deskew(dctx, preA)
			dcancel()
			if len(deskA) > 0 && len(deskA) != len(preA) {
				preA = deskA
			}
			variantCEnabled := os.Getenv("STOCK_PURCHASE_VARIANT_C") == "1"
			var preC []byte
			if variantCEnabled {
				preC = prepareTextractImageVariant(img.Data, 2)
			}
			var (
				itemsA, itemsB, itemsC []ExtractedPurchaseItem
				hdrA                   expenseHeader
				perrA, perrB, perrC    error
			)
			vg, vctx := errgroup.WithContext(gctx)
			vg.Go(func() error {
				itemsA, hdrA, perrA = runAnalyzeExpensePage(vctx, client, preA, i+1)
				return nil
			})
			vg.Go(func() error {
				itemsB, _, perrB = runAnalyzeExpensePage(vctx, client, preB, i+1)
				return nil
			})
			if variantCEnabled {
				vg.Go(func() error {
					itemsC, _, perrC = runAnalyzeExpensePage(vctx, client, preC, i+1)
					return nil
				})
			}
			_ = vg.Wait()
			if perrA != nil && perrB != nil && (!variantCEnabled || perrC != nil) {
				log.Printf("SmartPurchase expense: page %d variants failed: A=%v B=%v C=%v — escalating", i+1, perrA, perrB, perrC)
				pages[i] = perPage{idx: i, needsTx: true, needsLM: true, method: "expense_err"}
				return nil
			}
			items, hdr := itemsA, hdrA
			addedB, addedC := 0, 0
			if perrB == nil && len(itemsB) > 0 {
				items, addedB = mergeExpenseRowsBySNo(items, itemsB)
			}
			if variantCEnabled && perrC == nil && len(itemsC) > 0 {
				items, addedC = mergeExpenseRowsBySNoBottomCrop(items, itemsC)
			}
			useTables, useLLM := expenseNeedsFallback(items, hdr)
			pages[i] = perPage{
				idx:     i,
				items:   items,
				header:  hdr,
				needsTx: useTables,
				needsLM: useLLM,
				method:  "expense",
			}
			if variantCEnabled {
				log.Printf("SmartPurchase expense: page %d → %d items (A=%d B=%d+%d C=%d+%d), vendor=%q invoice=%q (needsTables=%v needsLLM=%v)",
					i+1, len(items), len(itemsA), len(itemsB), addedB, len(itemsC), addedC, hdr.VendorName, hdr.InvoiceNumber, useTables, useLLM)
			} else {
				log.Printf("SmartPurchase expense: page %d → %d items (A=%d B=%d+%d), vendor=%q invoice=%q (needsTables=%v needsLLM=%v)",
					i+1, len(items), len(itemsA), len(itemsB), addedB, hdr.VendorName, hdr.InvoiceNumber, useTables, useLLM)
			}
			return nil
		})
	}
	_ = g.Wait() // per-page errors swallowed; we set needsTx instead

	out := &expenseResult{
		PageMethods: make([]string, pageCount),
		NeedsTables: []int{},
		NeedsLLM:    []int{},
	}
	for _, p := range pages {
		out.PageMethods[p.idx] = p.method
		if p.needsTx {
			out.NeedsTables = append(out.NeedsTables, p.idx)
		}
		if p.needsLM {
			out.NeedsLLM = append(out.NeedsLLM, p.idx)
		}
		// v1.0.215.9 — stamp source page idx so SmartPurchaseExtractedItem
		// can carry the right page_index even when S.No collides across
		// pages (chhotu's bill: page 1 has 1-41, page 2 has 1-18).
		for k := range p.items {
			p.items[k].SourcePageIdx = p.idx
		}
		out.Items = append(out.Items, p.items...)
		// v1.0.239 — Vendor name merge: prefer the LIQUOR-VENDOR-LIKE candidate.
		// Pre-v239 we took whichever non-empty value landed first. Real-data
		// (chhotu's bill): page 1 emitted "Iconigota" (junk from a brand cell
		// mistagged as VENDOR_NAME) while page 2 correctly emitted "SONU SINGH
		// FL-2 2025-26". First-wins gave us "Iconigota". The new rule:
		//   1. Strong-match (contains FL-2/FL2/IMFL/WINE/BEVERAGE/Distributor) wins
		//   2. Else longest candidate wins (multi-word vendor names are more reliable)
		if p.header.VendorName != "" {
			cur := out.Header.VendorName
			cand := p.header.VendorName
			if scoreVendorCandidate(cand) > scoreVendorCandidate(cur) {
				out.Header.VendorName = cand
			}
		}
		if out.Header.VendorGST == "" && p.header.VendorGST != "" {
			out.Header.VendorGST = p.header.VendorGST
		}
		if out.Header.VendorAddress == "" && p.header.VendorAddress != "" {
			out.Header.VendorAddress = p.header.VendorAddress
		}
		if out.Header.InvoiceNumber == "" && p.header.InvoiceNumber != "" {
			out.Header.InvoiceNumber = p.header.InvoiceNumber
		}
		if out.Header.InvoiceDate == "" && p.header.InvoiceDate != "" {
			out.Header.InvoiceDate = p.header.InvoiceDate
		}
		// Totals are document-level, not per-page; the LAST page typically
		// carries the grand total but on single-page invoices it's just the
		// only page. Take the maximum non-zero — which gives the same
		// answer in both cases without needing page-position logic.
		if p.header.SubTotal > out.Header.SubTotal {
			out.Header.SubTotal = p.header.SubTotal
		}
		if p.header.TaxAmount > out.Header.TaxAmount {
			out.Header.TaxAmount = p.header.TaxAmount
		}
		if p.header.TotalAmount > out.Header.TotalAmount {
			out.Header.TotalAmount = p.header.TotalAmount
		}
		// Merge FieldConfidence maps so the header chip can show e.g.
		// "vendor confidence 0.93" if any one page reported it.
		if out.Header.FieldConfidence == nil {
			out.Header.FieldConfidence = map[string]float64{}
		}
		for k, v := range p.header.FieldConfidence {
			if cur, ok := out.Header.FieldConfidence[k]; !ok || v > cur {
				out.Header.FieldConfidence[k] = v
			}
		}
	}
	out.AnalyzeMethod = rollupMethod(out.PageMethods, len(out.NeedsTables), len(out.NeedsLLM))

	log.Printf("SmartPurchase expense: tenant=%s pages=%d items=%d header.vendor=%q header.invoice=%q method=%s elapsed=%dms",
		tenantID.String(), pageCount, len(out.Items),
		out.Header.VendorName, out.Header.InvoiceNumber,
		out.AnalyzeMethod, int(time.Since(startedAt).Milliseconds()))
	return out, nil
}

func rollupMethod(perPage []string, needsTx, needsLM int) string {
	if needsLM == len(perPage) {
		return "llm"
	}
	if needsTx > 0 {
		return "expense+tables"
	}
	return "expense"
}

// runAnalyzeExpensePage submits one page to AnalyzeExpense and converts the
// response into ExtractedPurchaseItem rows + an expenseHeader. Pure mapping;
// no math-gate here (called from the orchestrator after coalesce).
func runAnalyzeExpensePage(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
	pageNumber int,
) ([]ExtractedPurchaseItem, expenseHeader, error) {

	pctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	resp, hit, err := cachedAnalyzeExpense(pctx, client, raw)
	if err != nil {
		return nil, expenseHeader{}, fmt.Errorf("AnalyzeExpense: %w", err)
	}
	if hit {
		log.Printf("SmartPurchase expense: page %d served from cache (₹0)", pageNumber)
	}
	if resp == nil || len(resp.ExpenseDocuments) == 0 {
		return nil, expenseHeader{}, nil
	}

	doc := resp.ExpenseDocuments[0]
	items := mapExpenseToItems(doc, pageNumber)
	items = coalesceDualLineItems(items)
	items = applyExpenseMathGate(items)
	hdr := mapExpenseSummary(doc)
	return items, hdr, nil
}

// mergeExpenseRowsBySNoBottomCrop is the variant-C merge — bottom-crop
// rows that Textract may have re-numbered sequentially (its rowSerial 1
// = printed S.No 21 etc) instead of reading the printed S.No. To avoid
// false collisions ("row 1" from C colliding with "row 1" from A), we
// ONLY add C rows whose printed RowNumber exceeds max(items.RowNumber).
// In other words: variant C is purely a tail-extension — it can never
// overwrite or collide with rows we already trust from A+B.
//
// Returns (merged_items, count_added_from_C). Caller logs the count.
func mergeExpenseRowsBySNoBottomCrop(base, c []ExtractedPurchaseItem) ([]ExtractedPurchaseItem, int) {
	if len(c) == 0 {
		return base, 0
	}
	maxBaseSNo := 0
	bySNo := make(map[int]bool, len(base))
	for _, it := range base {
		sno := int(it.RowNumber)
		if sno > 0 {
			bySNo[sno] = true
			if sno > maxBaseSNo {
				maxBaseSNo = sno
			}
		}
	}
	out := base
	added := 0
	for _, cr := range c {
		sno := int(cr.RowNumber)
		if sno <= 0 {
			continue
		}
		if sno <= maxBaseSNo {
			continue // safety: only tail-extend, never overwrite
		}
		if bySNo[sno] {
			continue
		}
		out = append(out, cr)
		bySNo[sno] = true
		added++
	}
	return out, added
}

// mergeExpenseRowsBySNo unions variant-A + variant-B AnalyzeExpense outputs
// keyed on printed S.No (RowNumber). Rules:
//
//  - Variant A is the trusted base set (its rows are kept as-is).
//  - Variant B rows whose S.No is NOT in A are APPENDED as-is.
//  - Variant B rows whose S.No collides with A but has a more-complete
//    payload (Brand non-empty AND A's Brand was empty, OR QuantityBottles>0
//    AND A's was 0) REPLACE the A row. Otherwise A wins.
//  - S.No=0 rows (un-keyable) from B are skipped to avoid double-counting
//    the no-S.No rows A already emits.
//
// Returns (merged_items, count_added_from_B). Caller logs the count.
func mergeExpenseRowsBySNo(a, b []ExtractedPurchaseItem) ([]ExtractedPurchaseItem, int) {
	if len(a) == 0 {
		// Variant A failed but B produced rows — return B as the only signal.
		return append([]ExtractedPurchaseItem{}, b...), len(b)
	}
	out := make([]ExtractedPurchaseItem, len(a))
	copy(out, a)
	bySNo := make(map[int]int, len(out))
	for i, it := range out {
		sno := int(it.RowNumber)
		if sno > 0 {
			bySNo[sno] = i
		}
	}
	added := 0
	for _, br := range b {
		sno := int(br.RowNumber)
		if sno <= 0 {
			continue
		}
		idx, exists := bySNo[sno]
		if !exists {
			out = append(out, br)
			bySNo[sno] = len(out) - 1
			added++
			continue
		}
		ar := &out[idx]
		aEmpty := strings.TrimSpace(ar.Brand) == ""
		bHasBrand := strings.TrimSpace(br.Brand) != ""
		aQtyZero := ar.QuantityBottles <= 0 && ar.QuantityRaw <= 0
		bHasQty := br.QuantityBottles > 0 || br.QuantityRaw > 0
		if (aEmpty && bHasBrand) || (aQtyZero && bHasQty) {
			out[idx] = br
		}
	}
	return out, added
}

// applyExpenseMathGate corrects low-confidence QUANTITY values + reconciles
// per-bottle/per-case rate semantics using the invoice's amount-vs-rate
// identity. AnalyzeExpense's QUANTITY field on chhotu-class 720px phone JPEGs
// runs at 47-72% confidence (the printed "1 CS." / "21 CS." cells run together
// with adjacent ink and Textract OCR's "1" as "11"). Amount and Rate are
// 99-100% confident — they're typeset in clean rupee tables.
//
// Key insight: on UP IMFL invoices the "Rate" column is the per-CASE rate
// when the row is cases-denominated. So `amount = cases × rate` exactly,
// and `cases = amount / rate` derives the authoritative quantity from two
// high-confidence cells. We DON'T need to know BPC for this identity.
//
// We trust the amount/rate-derived value when:
//   - amount > 0 and rate > 0
//   - amount/rate lands on a clean small-integer (1-200 cases) with < 5%
//     residual against the closest integer
//
// Stamps Confidence to 0.95 on correction so the review UI flags the row.
//
// Side effect: when cases is derived, also set RatePerCase (= rate) and
// RatePerBottle (= rate/bpc) so the matcher sees both values consistently.
func applyExpenseMathGate(items []ExtractedPurchaseItem) []ExtractedPurchaseItem {
	for i := range items {
		it := &items[i]
		if it.Amount <= 0 || it.RatePerBottle <= 0 {
			continue
		}
		// "RatePerBottle" is misleading on the AnalyzeExpense path — for
		// cases-denominated rows it's actually the per-case rate. Use
		// generic name `rate` and derive both identities below.
		rate := it.RatePerBottle
		amount := it.Amount

		bpc := it.BottlesPerCase
		if bpc == 0 && it.SizeML > 0 {
			if std, ok := StandardCaseSizes[int(it.SizeML+0.5)]; ok {
				bpc = float64(std)
			}
		}

		qFromAmt := amount / rate
		qInt := math.Round(qFromAmt)
		if qInt < 1 {
			continue
		}
		if math.Abs(qFromAmt-qInt) > 0.05*qInt {
			continue // not a clean multiple — skip
		}

		// chhotu-class outlier rescue: when amount/rate yields a huge qty
		// (>50 cases) AND rate looks like a per-case rate (>₹1000), the
		// AMOUNT cell is almost certainly OCR-corrupt — Textract OCR'd a
		// missing decimal as in "8,003/26"=8003.26 → 800326 (10× error)
		// or even "13.434.64" → "13434.64" (which my parser handles, but
		// other slashes/spaces sneak through). Real liquor-invoice rows
		// almost never exceed 50 cases.
		//
		// Recovery: parse the trailing 1-2 digits of OCR_qty as the true
		// cases count. UP IMFL invoices print case counts as 1-2 digit
		// integers (1, 2, 3, ..., 12, max ~25), so the LEADING digits of
		// a 3-digit OCR_qty like "382" are almost always the previous
		// row's S.No bleeding into the cell.
		if qInt > 50 && rate >= 1000 {
			ocrQty := math.Round(it.QuantityRaw)
			tail := math.Mod(ocrQty, 100)
			if tail > 50 || tail == 0 {
				tail = math.Mod(ocrQty, 10)
			}
			if tail >= 1 && tail <= 50 {
				correctedAmt := rate * tail
				log.Printf("SmartPurchase expense outlier-rescue: brand=%q ocr_qty=%v leading-S.No bleed → tail=%v rate=%.2f amount %.2f → %.2f",
					it.Brand, ocrQty, tail, rate, amount, correctedAmt)
				it.Amount = correctedAmt
				amount = correctedAmt
				qInt = tail
				if it.QuantityFlag == "" {
					it.QuantityFlag = "amount_ocr_recovered"
				}
				if it.FieldConfidence == nil {
					it.FieldConfidence = map[string]float64{}
				}
				it.FieldConfidence["amount"] = 0.85
			}
		}

		// Decide whether qInt is "cases" or "bottles" using physical sanity:
		// - If qInt ≤ 200 AND bpc ≥ 6 AND rate is in the case-rate band
		//   (₹500 - ₹100,000), treat qInt as CASES and the rate as per-case.
		// - If qInt > 200 OR rate is in the bottle-rate band (₹30 - ₹500),
		//   treat qInt as BOTTLES and the rate as per-bottle.
		// For chhotu's invoices every row is cases-denominated; bottle-only
		// rows are extremely rare.
		isCases := false
		switch {
		case qInt <= 200 && bpc >= 6 && rate >= 500:
			isCases = true
		case qInt > 200, rate < 500 && rate >= 30:
			isCases = false
		default:
			// Ambiguous — fall back to the OCR'd unit hint.
			isCases = it.QuantityUnit == "cases" || it.QuantityUnit == ""
		}

		// Amount sanity check: when OCR'd amount disagrees with rate × qInt
		// by >5%, the amount itself is corrupt (slash-as-period, missing
		// digit, etc). Trust rate × qInt — it's the higher-confidence cell
		// product. Mark the row as needing review.
		expectedAmt := rate * qInt
		if expectedAmt > 0 && math.Abs(amount-expectedAmt) > 0.05*expectedAmt {
			log.Printf("SmartPurchase expense math-gate: brand=%q amount %.2f doesn't match rate*qty=%.2f → using rate*qty",
				it.Brand, amount, expectedAmt)
			it.Amount = expectedAmt
			amount = expectedAmt
			if it.QuantityFlag == "" {
				it.QuantityFlag = "amount_recomputed"
			}
		}

		if isCases {
			ocrCases := math.Round(it.QuantityRaw)
			changed := false
			if math.Abs(ocrCases-qInt) >= 1 {
				log.Printf("SmartPurchase expense math-gate: brand=%q OCR cases=%v → %v (rate_per_case=%.2f amount=%.2f bpc=%v)",
					it.Brand, ocrCases, qInt, rate, amount, bpc)
				it.QuantityRaw = qInt
				changed = true
			}
			it.QuantityUnit = "cases"
			it.RatePerCase = rate
			if bpc > 0 {
				it.RatePerBottle = rate / bpc // re-derive per-bottle rate
				it.BottlesPerCase = bpc
				// v1.0.239 — same Pcs-as-total override as the upstream cell-mapping path.
				casesTotal := qInt * bpc
				if it.LooseBottles > 0 && it.LooseBottles < casesTotal {
					it.QuantityBottles = it.LooseBottles
				} else if it.LooseBottles > 0 && it.LooseBottles == casesTotal {
					it.QuantityBottles = casesTotal
				} else {
					it.QuantityBottles = casesTotal + it.LooseBottles
				}
			}
			if changed {
				it.Confidence = 0.95
				if it.FieldConfidence == nil {
					it.FieldConfidence = map[string]float64{}
				}
				it.FieldConfidence["quantity"] = 0.95
				if it.QuantityFlag == "" {
					it.QuantityFlag = "math_gate_corrected"
				}
			}
		} else {
			// bottles-denominated row
			ocrBottles := math.Round(it.QuantityRaw)
			if math.Abs(ocrBottles-qInt) >= 1 {
				log.Printf("SmartPurchase expense math-gate: brand=%q OCR bottles=%v → %v (rate_per_bottle=%.2f amount=%.2f)",
					it.Brand, ocrBottles, qInt, rate, amount)
				it.QuantityRaw = qInt
				it.Confidence = 0.95
				if it.FieldConfidence == nil {
					it.FieldConfidence = map[string]float64{}
				}
				it.FieldConfidence["quantity"] = 0.95
				if it.QuantityFlag == "" {
					it.QuantityFlag = "math_gate_corrected"
				}
			}
			it.QuantityUnit = "bottles"
			it.QuantityBottles = qInt
		}
	}
	return items
}

// mapExpenseToItems converts every LineItemFields group into one
// ExtractedPurchaseItem. AnalyzeExpense returns each line item with a
// flat list of fields (ITEM, QUANTITY, UNIT_PRICE, PRICE, plus an OTHER
// bucket for everything Textract couldn't classify). For UP IMFL invoices
// the column carrying "5 Cs." lands as QUANTITY and "(60 Pcs)" usually
// lands either as a sibling LineItem (with ITEM blank) or smuggled into
// the same row's QUANTITY/ITEM text — both cases handled by
// coalesceDualLineItems below.
func mapExpenseToItems(doc ttypes.ExpenseDocument, pageNumber int) []ExtractedPurchaseItem {
	out := make([]ExtractedPurchaseItem, 0, 64)
	rowSerial := 0

	for _, group := range doc.LineItemGroups {
		for _, li := range group.LineItems {
			rowSerial++
			it := ExtractedPurchaseItem{
				RowNumber:       float64(rowSerial),
				FieldConfidence: map[string]float64{},
				AnalyzeMethod:   "expense",
			}
			otherBuf := []string{} // collects OTHER-tagged numerics for fallback
			otherFloats := []float64{}

			for _, f := range li.LineItemExpenseFields {
				tag := safeStr(f.Type, "Text")
				val := safeStr(f.ValueDetection, "Text")
				labelTxt := ""
				if f.LabelDetection != nil {
					labelTxt = strings.ToLower(safeStr(f.LabelDetection, "Text"))
				}
				conf := fieldConfidence(&f)
				switch tag {
				case "ITEM":
					it.Brand = cleanExpenseBrandText(val)
					if sz := parseSizeMLFromText(val); sz > 0 {
						it.SizeML = float64(sz)
						it.SizeText = fmt.Sprintf("%dml", sz)
					}
					it.FieldConfidence["brand"] = conf
				case "QUANTITY":
					qty, _ := parseNumericLike(val)
					if isCaseHint(val, labelTxt) || (qty > 0 && qty < 50) {
						it.QuantityRaw = qty
						it.QuantityUnit = "cases"
					} else if it.QuantityRaw == 0 {
						it.QuantityRaw = qty
						it.QuantityUnit = "bottles"
					}
					it.FieldConfidence["quantity"] = conf
					if pcs := extractParenthesizedPcs(val); pcs > 0 {
						it.LooseBottles = float64(pcs)
					}
				case "UNIT_PRICE":
					rate, _ := parseNumericLike(val)
					it.RatePerBottle = rate
					it.FieldConfidence["rate"] = conf
				case "PRICE":
					amt, _ := parseNumericLike(val)
					it.Amount = amt
					it.FieldConfidence["amount"] = conf
				case "EXPENSE_ROW", "SUPPLIER_ITEM_NUMBER", "PRODUCT_CODE", "ITEM_NUMBER":
					// Textract sometimes reports the printed S.No here; prefer
					// it over rowSerial when it parses cleanly, so the
					// review screen shows the same row numbers as the bill.
					if n, ok := parseIntFromText(val); ok && n > 0 && n < 1000 {
						it.RowNumber = float64(n)
					}
					// v1.0.239 — Textract sometimes drops "(N Pcs)" from the
					// QUANTITY field but joins it into the EXPENSE_ROW serial
					// text. Sweep EXPENSE_ROW for "(N Pcs)" and recover.
					if tag == "EXPENSE_ROW" && it.LooseBottles == 0 {
						if pcs := extractParenthesizedPcs(val); pcs > 0 {
							it.LooseBottles = float64(pcs)
						}
					}
				default:
					// OTHER / unknown — buffer for late fallback decisions
					if val != "" {
						otherBuf = append(otherBuf, val)
						if v, ok := parseNumericLike(val); ok {
							otherFloats = append(otherFloats, v)
						}
					}
				}
			}

			// Some excise invoices put bottles-per-case in an OTHER cell.
			// Use the smallest "small" number from OTHER if BPC is empty.
			if it.BottlesPerCase == 0 && len(otherFloats) > 0 {
				for _, v := range otherFloats {
					if v >= 6 && v <= 96 && (v == 12 || v == 24 || v == 48 || v == 96 || v == 9 || v == 8) {
						it.BottlesPerCase = v
						break
					}
				}
			}

			// QuantityBottles defaults to total when QuantityUnit == "bottles",
			// or cases × bpc when we know both. Math-gate (in the orchestrator
			// after Phase A coalesce) confirms / corrects this.
			//
			// v1.0.239 — Loose-dispatch override. UP IMFL bills sometimes
			// print "(N Pcs)" below a "M Cs" row to declare that the actual
			// physical count is N bottles, not M×BPC. Two patterns:
			//   "1 Cs (12 Pcs)"  → BPC confirmation, total = 12
			//   "2 Cs (24 Pcs)"  → BPC confirmation, total = 24
			//   "2 Cs (2 Pcs)"   → LOOSE dispatch, total = 2 (not 26 = 2×12+2)
			// Real-data (chhotu row 60 JW Black): "2 Cs (2 Pcs) × ₹2907.60 = ₹5815.20"
			// means 2 bottles at ₹2907.60/bottle. Pre-v239 we added the 2 Pcs ON TOP
			// of 2×12=24 → 26 bottles, wildly wrong. Now we treat LooseBottles as the
			// OVERRIDE TOTAL when it's strictly less than cases × bpc.
			if it.QuantityUnit == "bottles" {
				it.QuantityBottles = it.QuantityRaw
			} else if it.BottlesPerCase > 0 {
				casesTotal := it.QuantityRaw * it.BottlesPerCase
				if it.LooseBottles > 0 && it.LooseBottles < casesTotal {
					// Loose dispatch: bill is telling us actual bottles = LooseBottles
					it.QuantityBottles = it.LooseBottles
				} else if it.LooseBottles > 0 && it.LooseBottles == casesTotal {
					// BPC confirmation: standard math
					it.QuantityBottles = casesTotal
				} else {
					// Either no Pcs annotation or Pcs > cases×bpc (additional loose
					// on top of full cases — keep legacy add behavior).
					it.QuantityBottles = casesTotal + it.LooseBottles
				}
			}

			// Per-row aggregate confidence = mean of populated FieldConfidence
			// entries (matches the convention in textract_purchase_pipeline.go).
			if len(it.FieldConfidence) > 0 {
				sum := 0.0
				for _, c := range it.FieldConfidence {
					sum += c
				}
				it.Confidence = sum / float64(len(it.FieldConfidence))
			}

			// Low-confidence guard: any of {brand, quantity, amount} below 0.75
			// flags the row for operator review.
			if floor(it.FieldConfidence, "brand") < 0.75 ||
				floor(it.FieldConfidence, "quantity") < 0.75 ||
				floor(it.FieldConfidence, "amount") < 0.75 {
				if it.QuantityFlag == "" {
					it.QuantityFlag = "low_confidence_field"
				}
			}

			// Empty rows happen when Textract emits a placeholder LineItem
			// for blank rule lines. Skip them; the row counter will renumber
			// naturally on the next iteration.
			if it.Brand == "" && it.QuantityRaw == 0 && it.Amount == 0 {
				rowSerial--
				continue
			}
			out = append(out, it)
		}
	}
	_ = pageNumber
	return out
}

// coalesceDualLineItems merges visually-stacked dual-line cells into the
// previous row. Two patterns we've seen on real chhotu invoices:
//
//  1. AnalyzeExpense splits the visual cell into two LineItems where the
//     second has empty ITEM and a "(60 Pcs)" string somewhere. We detect
//     a row whose Brand is empty AND has no Amount/Rate but does carry a
//     parenthesized "(N Pcs)" — fold N into the prior row's LooseBottles.
//
//  2. AnalyzeExpense merges them: ITEM = "5 Cs." / QUANTITY = "5 (60 Pcs)".
//     We extract the parenthesized number from the QUANTITY value during
//     mapping (above) and store it in LooseBottles.
//
// After coalesce, the orchestrator's existing pack-math gate
// (textract_purchase_pipeline.go:186-247) reconciles cases × BPC ± loose
// against the QuantityBottles value.
func coalesceDualLineItems(items []ExtractedPurchaseItem) []ExtractedPurchaseItem {
	if len(items) <= 1 {
		return items
	}
	out := make([]ExtractedPurchaseItem, 0, len(items))
	for i := 0; i < len(items); i++ {
		cur := items[i]
		// Pattern 1 detector: empty brand, no rate, no amount, just a
		// "(N Pcs)" annotation in some text field somewhere.
		if cur.Brand == "" && cur.RatePerBottle == 0 && cur.Amount == 0 && len(out) > 0 {
			lastIdx := len(out) - 1
			if cur.LooseBottles > 0 {
				out[lastIdx].LooseBottles += cur.LooseBottles
				// v1.0.239 — recompute QuantityBottles with Pcs-as-total override.
				if out[lastIdx].QuantityUnit == "cases" && out[lastIdx].BottlesPerCase > 0 {
					casesTotal := out[lastIdx].QuantityRaw * out[lastIdx].BottlesPerCase
					loose := out[lastIdx].LooseBottles
					if loose > 0 && loose < casesTotal {
						out[lastIdx].QuantityBottles = loose
					} else if loose > 0 && loose == casesTotal {
						out[lastIdx].QuantityBottles = casesTotal
					} else {
						out[lastIdx].QuantityBottles = casesTotal + loose
					}
				}
				continue
			}
			// Even when LooseBottles is 0, an orphan empty row should be
			// dropped (it's just visual noise from the stacked-cell split).
			continue
		}
		out = append(out, cur)
	}
	return out
}

// mapExpenseSummary lifts the document-level SummaryFields off the response.
// AnalyzeExpense's standard tags cover everything we need for UP IMFL
// invoices. When a tag is missing on the primary page, the orchestrator
// can run a secondary AnalyzeDocument(QUERIES) call (Phase B3) — but that
// rarely fires once Expense is the primary.
func mapExpenseSummary(doc ttypes.ExpenseDocument) expenseHeader {
	hdr := expenseHeader{FieldConfidence: map[string]float64{}}
	for _, f := range doc.SummaryFields {
		tag := safeStr(f.Type, "Text")
		val := strings.TrimSpace(safeStr(f.ValueDetection, "Text"))
		conf := fieldConfidence(toLineField(f))
		switch tag {
		case "VENDOR_NAME":
			// v1.0.239 — VENDOR_NAME is always the SELLER. Take it
			// unconditionally; receiver/party names live in RECEIVER_NAME.
			hdr.VendorName = val
			hdr.FieldConfidence["vendor"] = conf
		case "RECEIVER_NAME", "NAME":
			// Only fall back to RECEIVER_NAME / NAME when no proper VENDOR_NAME
			// has been emitted. Real-data: chhotu's SONU SINGH FL-2 bill labels
			// "SONU SINGH FL-2 2025-26" as VENDOR_NAME and "Radhika Agrawal Comp
			// Mahuakheda" (the buyer) as RECEIVER_NAME. Pre-v239 we picked
			// whichever was emitted first, often the buyer — that's now fixed.
			if hdr.VendorName == "" {
				hdr.VendorName = val
				hdr.FieldConfidence["vendor"] = conf
			}
		case "VENDOR_VAT_NUMBER", "VENDOR_GST_NUMBER", "TAX_PAYER_ID", "VAT_NUMBER":
			if hdr.VendorGST == "" {
				hdr.VendorGST = val
				hdr.FieldConfidence["vendor_gst"] = conf
			}
		case "VENDOR_ADDRESS", "STREET", "ADDRESS":
			if hdr.VendorAddress == "" {
				hdr.VendorAddress = val
				hdr.FieldConfidence["vendor_address"] = conf
			}
		case "INVOICE_RECEIPT_ID", "RECEIPT_ID":
			if hdr.InvoiceNumber == "" {
				hdr.InvoiceNumber = val
				hdr.FieldConfidence["invoice_number"] = conf
			}
		case "INVOICE_RECEIPT_DATE", "RECEIPT_DATE":
			if hdr.InvoiceDate == "" {
				hdr.InvoiceDate = val
				hdr.FieldConfidence["invoice_date"] = conf
			}
		case "SUBTOTAL":
			if v, ok := parseNumericLike(val); ok {
				hdr.SubTotal = v
				hdr.FieldConfidence["subtotal"] = conf
			}
		case "TAX":
			if v, ok := parseNumericLike(val); ok {
				hdr.TaxAmount = v
				hdr.FieldConfidence["tax"] = conf
			}
		case "TOTAL", "AMOUNT_DUE", "AMOUNT_PAID":
			if v, ok := parseNumericLike(val); ok {
				if v > hdr.TotalAmount {
					hdr.TotalAmount = v
					hdr.FieldConfidence["total"] = conf
				}
			}
		}
	}
	return hdr
}

// expenseNeedsFallback decides whether this page's AnalyzeExpense output
// is good enough to ship, or whether we need to escalate to either
// AnalyzeDocument(TABLES) or — in the worst case — the LLM cascade.
//
// Returns (useTables, useLLM):
//
//	useTables=true : items missing or low-confidence — try TABLES on this page
//	useLLM=true    : Expense AND TABLES both produced almost nothing — last resort
//
// Per-page (not per-submission) so a single bad page doesn't burn the whole
// job's cost on LLM.
func expenseNeedsFallback(items []ExtractedPurchaseItem, hdr expenseHeader) (useTables bool, useLLM bool) {
	if len(items) == 0 && hdr.VendorName == "" && hdr.TotalAmount == 0 {
		// Hard failure — no items, no header signal at all.
		return true, true
	}
	if len(items) == 0 {
		// Header looked OK (vendor or total recovered) but no line items —
		// definitely worth a TABLES re-pass. LLM only if TABLES also fails.
		return true, false
	}
	medianConf := medianRowConfidence(items)
	if medianConf < 0.75 {
		return true, false
	}
	// Reconciliation: if we have both a header total and item amounts, check
	// |sum_amounts - total| / total. >10% diff means likely missing rows.
	if hdr.TotalAmount > 0 {
		sum := 0.0
		for _, it := range items {
			sum += it.Amount
		}
		if sum > 0 {
			diff := math.Abs(sum-hdr.TotalAmount) / hdr.TotalAmount
			if diff > 0.10 {
				return true, false
			}
		}
	}
	return false, false
}

// textractClearlyFailed is the single source of truth for the "did Textract
// do nothing useful?" question. Used by the orchestrator to decide whether
// to call the LLM cascade after both Expense + TABLES have run.
func textractClearlyFailed(items []ExtractedPurchaseItem, hdr expenseHeader) bool {
	if len(items) == 0 && hdr.VendorName == "" && hdr.InvoiceNumber == "" && hdr.TotalAmount == 0 {
		return true
	}
	return false
}

// medianRowConfidence over Confidence (post-mapping aggregate).
func medianRowConfidence(items []ExtractedPurchaseItem) float64 {
	if len(items) == 0 {
		return 0
	}
	cs := make([]float64, 0, len(items))
	for _, it := range items {
		if it.Confidence > 0 {
			cs = append(cs, it.Confidence)
		}
	}
	if len(cs) == 0 {
		return 0
	}
	sort.Float64s(cs)
	mid := len(cs) / 2
	if len(cs)%2 == 1 {
		return cs[mid]
	}
	return (cs[mid-1] + cs[mid]) / 2.0
}

// ---------- helpers (kept local to this file to avoid colliding with the
// existing parseIntPurchaseCell / parseFloatPurchaseCell helpers in the
// TABLES pipeline, which take Block arguments) ----------

var (
	pcsRe = regexp.MustCompile(`(?i)\(?\s*(\d+)\s*(?:pcs?|pieces|btls?|bottles?)\s*\)?`)

	// brandLeadingDigitsRe strips up to 3 leading digits + whitespace from
	// the start of an ITEM string. AnalyzeExpense on chhotu-class invoices
	// frequently merges the S.No column into the ITEM cell when the row
	// is tightly packed — we see "11 ROYAL GREEN", "44 100 Strokes", etc.
	// where the leading number is the printed serial number, not part of
	// the brand name.
	brandLeadingDigitsRe = regexp.MustCompile(`^\d{1,3}\s+`)

	// brandTrailingDigitsRe strips a trailing single-digit run that's
	// likely Textract bleeding the next column's case-count into the ITEM
	// text. Conservative: only kills 1-2 digits, never anything that could
	// be part of a real brand name like "100" or "1980" or "750".
	brandTrailingDigitsRe = regexp.MustCompile(`\s+\d{1,2}$`)
)

// cleanExpenseBrandText normalises an AnalyzeExpense ITEM value so the
// brand-matcher gets the clean brand name without leading S.No or trailing
// case-count digits. Pure string manipulation; doesn't lose the raw text
// (caller still has access to the LineItem's other fields).
func cleanExpenseBrandText(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return s
	}
	// Strip leading "11 " / "44 " — the S.No bleed-in.
	s = brandLeadingDigitsRe.ReplaceAllString(s, "")
	// Don't strip trailing digits if they're part of a size like "180ml" or
	// "750" — only strip when there's a clear word-then-digit suffix.
	if !strings.HasSuffix(strings.ToLower(s), "ml") &&
		!regexp.MustCompile(`\d{3}$`).MatchString(s) {
		s = brandTrailingDigitsRe.ReplaceAllString(s, "")
	}
	return strings.TrimSpace(s)
}

// scoreVendorCandidate ranks a candidate vendor-name string. Higher is better.
// v1.0.239 — used by cross-page vendor merge to pick the most-vendor-shaped
// value when multiple pages emit different VENDOR_NAME tokens.
func scoreVendorCandidate(s string) int {
	v := strings.TrimSpace(s)
	if v == "" {
		return -1
	}
	score := 0
	upper := strings.ToUpper(v)
	// Liquor-vendor signals — pattern-matching the FL-2 / IMFL / wine /
	// beverage license codes that appear in real Indian liquor invoice
	// headers.
	strongTokens := []string{"FL-2", "FL2", "IMFL", "WINE", "BEVERAGE", "BREWERY", "DISTILLER", "DISTRIBUTOR", "TRADERS", "AGENCY", "DEPOT"}
	for _, tok := range strongTokens {
		if strings.Contains(upper, tok) {
			score += 100
			break
		}
	}
	// Multi-word names score more (real vendors usually have 2+ words).
	words := strings.Fields(v)
	score += len(words) * 2
	// Length signal (longer strings less likely to be a brand-token misread).
	score += len(v) / 8
	// Penalise garbage signals — mostly-lowercase short blobs are usually
	// brand cells, not headers.
	if len(v) <= 12 && strings.ToLower(v) == v {
		score -= 50
	}
	return score
}

func extractParenthesizedPcs(s string) int {
	if s == "" {
		return 0
	}
	m := pcsRe.FindStringSubmatch(s)
	if len(m) < 2 {
		return 0
	}
	n, err := strconv.Atoi(m[1])
	if err != nil || n <= 0 || n > 2000 {
		return 0
	}
	return n
}

// parseNumericLike strips currency / unit decoration off a Textract value
// and parses what remains as a float. Handles two real-world OCR errors
// observed on chhotu's 720px phone JPEGs (v1.0.199):
//
//  1. Slash-as-decimal: "8,003/26" parses to 8003.26. Textract's vision
//     model reads a smudged decimal point as a forward slash about 5% of
//     the time on high-res zoom in.
//  2. Double-decimal:   "13.434.64" parses to 13434.64. The lakh comma
//     ("13,434.64") gets read as a period when the comma stroke is faint.
//     We collapse all but the LAST period — that one is the real decimal
//     separator on Indian-formatted rupee values.
//
// Returns (value, ok). ok=false on empty / unparseable strings.
func parseNumericLike(s string) (float64, bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, false
	}
	// Strip currency symbols / units / commas; treat "/" as "." (OCR
	// mis-reads the decimal point).
	cleaned := strings.Map(func(r rune) rune {
		switch {
		case r >= '0' && r <= '9', r == '.', r == '-':
			return r
		case r == '/':
			return '.'
		}
		return -1
	}, s)
	cleaned = strings.TrimRight(cleaned, ".") // trailing "5."
	if cleaned == "" {
		return 0, false
	}
	// Collapse multiple periods, keeping only the last one. "13.434.64" →
	// "13434.64". This mimics Indian lakh formatting where commas are
	// optional thousands separators and the final "." is the decimal.
	if strings.Count(cleaned, ".") > 1 {
		idx := strings.LastIndex(cleaned, ".")
		cleaned = strings.ReplaceAll(cleaned[:idx], ".", "") + cleaned[idx:]
	}
	v, err := strconv.ParseFloat(cleaned, 64)
	if err != nil {
		return 0, false
	}
	return v, true
}

func parseIntFromText(s string) (int, bool) {
	v, ok := parseNumericLike(s)
	if !ok {
		return 0, false
	}
	if v != math.Trunc(v) || v < 0 {
		return 0, false
	}
	return int(v), true
}

// isCaseHint returns true when either the value text or the field's
// LabelDetection text strongly implies a case-denominated quantity.
// "5 Cs." / "5 cases" / "5 case" / "ctn" all map to cases; "60 pcs"
// / "60 bottles" / "(60 Pcs)" map to bottles (handled separately).
func isCaseHint(val, label string) bool {
	v := strings.ToLower(val)
	if strings.Contains(v, "cs.") || strings.Contains(v, "cs ") || strings.HasSuffix(v, "cs") ||
		strings.Contains(v, "case") || strings.Contains(v, "ctn") || strings.Contains(v, "carton") {
		return true
	}
	if label == "" {
		return false
	}
	return strings.Contains(label, "case") || strings.Contains(label, "carton") || strings.Contains(label, "ctn")
}

// safeStr extracts a string from any AWS expense field-detection sub-struct
// whose "Text" pointer might be nil. AWS SDK v2 returns *string everywhere
// so a tiny reflection-free helper saves a lot of nil checks at call sites.
func safeStr(v interface{}, field string) string {
	switch x := v.(type) {
	case *ttypes.ExpenseType:
		if x != nil && x.Text != nil {
			return *x.Text
		}
	case *ttypes.ExpenseDetection:
		if x != nil && x.Text != nil {
			return *x.Text
		}
	}
	_ = field
	return ""
}

// fieldConfidence pulls the average of label + value confidence (each is
// a 0-100 float in AWS SDK v2; we return 0-1 to match the rest of the
// codebase's conf scale).
func fieldConfidence(f *ttypes.ExpenseField) float64 {
	if f == nil {
		return 0
	}
	confs := []float64{}
	if f.LabelDetection != nil && f.LabelDetection.Confidence != nil {
		confs = append(confs, float64(*f.LabelDetection.Confidence)/100.0)
	}
	if f.ValueDetection != nil && f.ValueDetection.Confidence != nil {
		confs = append(confs, float64(*f.ValueDetection.Confidence)/100.0)
	}
	if len(confs) == 0 {
		return 0
	}
	sum := 0.0
	for _, c := range confs {
		sum += c
	}
	return sum / float64(len(confs))
}

// toLineField wraps a SummaryField to share fieldConfidence's calculation.
// AWS SDK v2 has separate ExpenseField + the SummaryField is itself an
// ExpenseField — so this is a no-op pointer cast.
func toLineField(f ttypes.ExpenseField) *ttypes.ExpenseField { return &f }

// floor returns the value at key or 1.0 (treat absence as confident — we
// don't want to flag a row low-confidence just because Textract didn't
// emit a particular field).
func floor(m map[string]float64, key string) float64 {
	if m == nil {
		return 1
	}
	if v, ok := m[key]; ok {
		return v
	}
	return 1
}


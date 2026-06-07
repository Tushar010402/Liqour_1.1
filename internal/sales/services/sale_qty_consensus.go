package services

import (
	"fmt"
	"math"
	"os"
)

// v1.0.134 Track E — tri-source consensus for sale_quantity.
//
// On the Sale register the AI extracts five primary numbers per row:
//   opening, closing, receipt, sale_qty, rate, amount
//
// Three independent signals can corroborate sale_qty:
//   S1: direct OCR of the sale_qty cell                  (item.Quantity)
//   S2: stock identity   opening + receipt − closing     (math)
//   S3: amount divided by rate                            (round(amount/rate))
//
// Consensus rules (highest precision wins):
//   - All three agree                       → trust S1, force conf 0.99
//   - Two-of-three agree                    → set Quantity to majority,
//                                              expose alternatives via warnings
//   - Disagreement / single signal          → drop sale-cell conf so Flutter
//                                              renders amber + surface all
//                                              candidates as warnings
//
// This runs BEFORE the existing math-gate logic so the existing math-gate
// continues to handle the "math wins after auto-apply" cosmetic chip path.
// We only adjust Quantity in the multi-source-agree case so the math-gate
// auto-apply continues to fire on its own narrow column-drift signature.
//
// Toggle off with SMART_SALE_QTY_CONSENSUS=0. Defaults to ON.

const (
	consensusOpenCloseConfMin = 0.85 // both opening AND closing must be ≥ this for S2
	consensusAmountRateConfMin = 0.85 // both amount AND rate must be ≥ this for S3
)

// SaleConsensusStats is reported per-job for telemetry.
type SaleConsensusStats struct {
	Rows3of3         int
	Rows2of3         int
	RowsDisagree     int
	RowsSingleOnly   int
	QtyOverwrites    int
	BackfillDetected int
}

func intAbs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func consensusEnabled() bool {
	return os.Getenv("SMART_SALE_QTY_CONSENSUS") != "0"
}

// applySaleQtyConsensus mutates items in place. Returns per-job telemetry.
//
// Item field semantics (from SmartSaleExtractedItem):
//   Quantity         int      — S1
//   OpeningStock     *int     — used in S2
//   Receipt          *int     — used in S2
//   ClosingStock     *int     — used in S2
//   Rate             float64  — used in S3
//   Amount           float64  — used in S3
//   FieldConfidence  map[string]float64
//
// We never *lower* the consensus value below the AI's read — we only override
// Quantity when ≥2 sources agree on a *different* number than the AI gave.
func applySaleQtyConsensus(items []SmartSaleExtractedItem) ([]SmartSaleExtractedItem, SaleConsensusStats) {
	stats := SaleConsensusStats{}
	if !consensusEnabled() {
		return items, stats
	}
	for i := range items {
		row := &items[i]
		// Only operate when the AI claimed a positive sale qty — Track E is a
		// confirmation pass, not a row-creation pass. Zero-qty rows fall through
		// untouched and are still handled by the existing IsZeroQuantity flow.
		if row.Quantity <= 0 {
			continue
		}
		s1 := row.Quantity
		var s2, s3 int
		s2Ok, s3Ok := false, false

		if row.OpeningStock != nil && row.ClosingStock != nil {
			openConf, openOk := safeConf(row.FieldConfidence, "opening")
			closeConf, closeOk := safeConf(row.FieldConfidence, "closing")
			if (!openOk || openConf >= consensusOpenCloseConfMin) &&
				(!closeOk || closeConf >= consensusOpenCloseConfMin) {
				recpt := 0
				if row.Receipt != nil {
					recpt = *row.Receipt
				}
				delta := *row.OpeningStock + recpt - *row.ClosingStock
				if delta > 0 && delta <= *row.OpeningStock+recpt {
					s2 = delta
					s2Ok = true
				}
			}
		}
		if row.Rate > 0 && row.Amount > 0 {
			rateConf, rateOk := safeConf(row.FieldConfidence, "rate")
			amtConf, amtOk := safeConf(row.FieldConfidence, "amount")
			if (!rateOk || rateConf >= consensusAmountRateConfMin) &&
				(!amtOk || amtConf >= consensusAmountRateConfMin) {
				div := int(math.Round(row.Amount / row.Rate))
				if div > 0 && div < 10000 {
					s3 = div
					s3Ok = true
				}
			}
		}

		// v1.0.159 — Back-fill tautology detector. When the AI cannot read the
		// amount cell, older prompts told it to compute amount = sale × rate,
		// which makes S3 (amount÷rate) round-trip to S1 with zero residual. That
		// silently confirms a wrong qty when stock-math (S2) disagrees. Detect
		// the signature: S2 disagrees by ≥3 AND S3 == S1 AND residual = 0.
		// In that case, exclude S3 so consensus correctly surfaces math-disagree
		// for mandatory operator review (Flutter math-fail red chip on v1.0.158).
		// We require S2 disagreement so we never demote a legitimate row where
		// AI just read all three cells correctly.
		backfillDetectedThisRow := false
		if s2Ok && s3Ok && s3 == s1 && intAbs(s2-s1) >= 3 {
			residual := math.Abs(row.Amount - float64(s1)*row.Rate)
			if residual < 0.5 { // FP-precision exactness
				s3Ok = false
				backfillDetectedThisRow = true
				row.Warnings = append(row.Warnings,
					fmt.Sprintf("Amount cell appears back-filled (= %d × ₹%.0f exactly); stock-math suggests qty=%d", s1, row.Rate, s2))
				if row.FieldConfidence == nil {
					row.FieldConfidence = map[string]float64{}
				}
				if row.FieldConfidence["amount"] == 0 || row.FieldConfidence["amount"] > 0.5 {
					row.FieldConfidence["amount"] = 0.5
				}
				stats.BackfillDetected++
			}
		}

		// v1.0.159 — When back-fill was detected, S2 is the only INDEPENDENT
		// signal of qty (deterministic arithmetic on 3 OCR'd cells). If S2 is
		// in a plausible range (0.3x – 3x of S1) and confidence on opening AND
		// closing is high, override qty to S2 with mandatory review.
		if backfillDetectedThisRow && s2Ok && intAbs(s2-s1) >= 3 {
			openConf, _ := safeConf(row.FieldConfidence, "opening")
			closeConf, _ := safeConf(row.FieldConfidence, "closing")
			ratio := float64(s2) / float64(s1)
			if openConf >= 0.90 && closeConf >= 0.90 && ratio >= 0.3 && ratio <= 3.0 {
				prev := row.Quantity
				row.Quantity = s2
				row.Amount = float64(s2) * row.Rate
				if row.OriginalAIQuantity == nil {
					prevCopy := prev
					row.OriginalAIQuantity = &prevCopy
				}
				row.Warnings = append(row.Warnings,
					fmt.Sprintf("✓ Sale qty corrected to %d via stock-math (open+recpt-close); back-fill detected on AI read %d", s2, prev))
				row.NeedsReview = true
				if row.FieldConfidence == nil {
					row.FieldConfidence = map[string]float64{}
				}
				row.FieldConfidence["sale"] = 0.88
				stats.QtyOverwrites++
				continue
			}
		}

		signals := 1
		agreeS1S2 := s2Ok && s2 == s1
		agreeS1S3 := s3Ok && s3 == s1
		agreeS2S3 := s2Ok && s3Ok && s2 == s3
		if s2Ok {
			signals++
		}
		if s3Ok {
			signals++
		}

		switch {
		case agreeS1S2 && agreeS1S3:
			stats.Rows3of3++
			row.Confidence = maxFloat(row.Confidence, 0.99)
			if row.FieldConfidence == nil {
				row.FieldConfidence = map[string]float64{}
			}
			row.FieldConfidence["sale"] = maxFloat(row.FieldConfidence["sale"], 0.99)
		case agreeS1S2 && !agreeS1S3 && s3Ok:
			stats.Rows2of3++
			row.Warnings = append(row.Warnings,
				fmt.Sprintf("Sale qty %d agrees with stock math; amount/rate suggests %d", s1, s3))
		case agreeS1S3 && !agreeS1S2 && s2Ok:
			stats.Rows2of3++
			row.Warnings = append(row.Warnings,
				fmt.Sprintf("Sale qty %d agrees with amount÷rate; stock math suggests %d", s1, s2))
		case agreeS2S3 && !agreeS1S2:
			// AI alone disagrees with two corroborating sources — overwrite.
			stats.Rows2of3++
			stats.QtyOverwrites++
			prev := row.Quantity
			row.Quantity = s2
			row.Amount = float64(s2) * row.Rate
			if row.OriginalAIQuantity == nil {
				prevCopy := prev
				row.OriginalAIQuantity = &prevCopy
			}
			row.Warnings = append(row.Warnings,
				fmt.Sprintf("✓ Sale qty corrected to %d (math + amount÷rate both agree; AI read %d)", s2, prev))
			row.NeedsReview = true
			if row.FieldConfidence == nil {
				row.FieldConfidence = map[string]float64{}
			}
			row.FieldConfidence["sale"] = 0.95
		case signals >= 2:
			// 2 of 3 disagreed — surface as low-confidence with all candidates.
			//
			// v1.0.159 — Clean-divide S3 override. If the amount÷rate signal
			// divides exactly (residual < 5% of rate), it's deterministic
			// arithmetic on two OCR cells the AI rated highly. When s1
			// disagrees by ≥2 AND s3 is clean AND s3 ≠ s2, the AI digit
			// almost certainly misread (faded ink) — override to s3.
			// We require rate confidence ≥0.90 and amount confidence ≥0.90
			// (stricter than the consensusAmountRateConfMin gate above) so
			// we never override on shaky inputs.
			if s3Ok && abs(s3-s1) >= 2 && (!s2Ok || s2 != s3) {
				rateConf, _ := safeConf(row.FieldConfidence, "rate")
				amtConf, _ := safeConf(row.FieldConfidence, "amount")
				residual := math.Abs(row.Amount - float64(s3)*row.Rate)
				if residual < row.Rate*0.05 && rateConf >= 0.90 && amtConf >= 0.90 {
					stats.Rows2of3++
					stats.QtyOverwrites++
					prev := row.Quantity
					row.Quantity = s3
					row.Amount = float64(s3) * row.Rate
					if row.OriginalAIQuantity == nil {
						prevCopy := prev
						row.OriginalAIQuantity = &prevCopy
					}
					row.Warnings = append(row.Warnings,
						fmt.Sprintf("✓ Sale qty corrected to %d (amount÷rate exact; AI read %d)", s3, prev))
					row.NeedsReview = true
					if row.FieldConfidence == nil {
						row.FieldConfidence = map[string]float64{}
					}
					row.FieldConfidence["sale"] = 0.92
					continue
				}
			}
			stats.RowsDisagree++
			row.Warnings = append(row.Warnings,
				fmt.Sprintf("Sale qty unclear: OCR=%d math=%s amount÷rate=%s",
					s1, intOrDash(s2, s2Ok), intOrDash(s3, s3Ok)))
			row.NeedsReview = true
			if row.FieldConfidence == nil {
				row.FieldConfidence = map[string]float64{}
			}
			if cur, ok := row.FieldConfidence["sale"]; !ok || cur > 0.6 {
				row.FieldConfidence["sale"] = 0.55
			}
		default:
			stats.RowsSingleOnly++
		}
	}
	return items, stats
}

func safeConf(m map[string]float64, k string) (float64, bool) {
	if m == nil {
		return 0, false
	}
	v, ok := m[k]
	return v, ok
}

func maxFloat(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func intOrDash(v int, ok bool) string {
	if !ok {
		return "—"
	}
	return fmt.Sprintf("%d", v)
}

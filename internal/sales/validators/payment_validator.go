package validators

import (
	"fmt"
	"math"
)

// PaymentBreakdown represents the payment amounts for validation
type PaymentBreakdown struct {
	Cash     float64
	Card     float64
	UPI      float64
	Credit   float64
	Expenses float64
	Total    float64
}

// ValidatePaymentBreakdown validates that payment methods sum to the total amount.
// Formula: Cash + Card + UPI + Credit + Expenses = Total
// Expenses are paid from collected cash, so they count towards the total.
//
// Example:
//   - GrossSales = 18320
//   - Expenses = 20 (paid from cash)
//   - NetCash = 18300
//   - Validation: 18300 + 0 + 0 + 0 + 20 = 18320 ✓
func ValidatePaymentBreakdown(breakdown PaymentBreakdown) error {
	sum := breakdown.Cash + breakdown.Card + breakdown.UPI + breakdown.Credit + breakdown.Expenses
	if math.Abs(sum-breakdown.Total) > 0.01 {
		return fmt.Errorf("payment mismatch: Cash(%.2f) + Card(%.2f) + UPI(%.2f) + Credit(%.2f) + Expenses(%.2f) = %.2f, expected %.2f (diff=%.2f)",
			breakdown.Cash, breakdown.Card, breakdown.UPI, breakdown.Credit, breakdown.Expenses,
			sum, breakdown.Total, sum-breakdown.Total)
	}
	return nil
}

// ValidatePaymentAmounts is a simpler version that takes individual amounts
// Formula: Cash + Card + UPI + Credit + Expenses = Total
func ValidatePaymentAmounts(cash, card, upi, credit, expenses, total float64) error {
	return ValidatePaymentBreakdown(PaymentBreakdown{
		Cash:     cash,
		Card:     card,
		UPI:      upi,
		Credit:   credit,
		Expenses: expenses,
		Total:    total,
	})
}

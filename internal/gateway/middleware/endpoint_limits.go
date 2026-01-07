package middleware

import (
	"github.com/gin-gonic/gin"
	sharedMiddleware "github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// RegisterEndpointLimits configures all endpoint-specific rate limits
// These limits are applied BEFORE authentication for public endpoints
// and use Redis for distributed rate limiting across gateway instances
func RegisterEndpointLimits(limiter *sharedMiddleware.RedisRateLimiter) {
	// === VALIDATION ENDPOINTS (Enumeration Prevention) ===
	// These are critical for preventing user enumeration attacks

	// Phone validation: 10/min per IP (prevents phone number enumeration)
	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/admin/validate/phone",
		RequestsPerMinute: 10,
		IdentifierFunc:    sharedMiddleware.GetIPIdentifier,
		KeyPrefix:         "validate_phone",
	})

	// Email validation: 10/min per IP (prevents email enumeration)
	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/admin/validate/email",
		RequestsPerMinute: 10,
		IdentifierFunc:    sharedMiddleware.GetIPIdentifier,
		KeyPrefix:         "validate_email",
	})

	// Tenant name validation: 30/min per IP (less critical)
	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/admin/validate/tenant",
		RequestsPerMinute: 30,
		IdentifierFunc:    sharedMiddleware.GetIPIdentifier,
		KeyPrefix:         "validate_tenant",
	})

	// === OTP ENDPOINTS (OTP Bombing Prevention) ===
	// Critical - OTP bombing can drain SMS credits and annoy users

	// OTP for registration: 5/min per phone/IP
	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/auth/send-otp-registration",
		RequestsPerMinute: 5,
		IdentifierFunc:    sharedMiddleware.GetPhoneOrIPIdentifier,
		KeyPrefix:         "otp_registration",
	})

	// General OTP: 5/min per phone/IP
	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/auth/send-otp",
		RequestsPerMinute: 5,
		IdentifierFunc:    sharedMiddleware.GetPhoneOrIPIdentifier,
		KeyPrefix:         "otp_send",
	})

	// OTP verification: 10/min per IP to allow retries
	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/auth/verify-otp",
		RequestsPerMinute: 10,
		IdentifierFunc:    sharedMiddleware.GetIPIdentifier,
		KeyPrefix:         "otp_verify",
	})

	// === AUTH ENDPOINTS (Brute Force Prevention) ===
	// Note: Login lockout is handled separately by LoginRateLimiter
	// These provide additional request rate protection

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/auth/login",
		RequestsPerMinute: 10,
		IdentifierFunc:    sharedMiddleware.GetIPIdentifier,
		KeyPrefix:         "login",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/auth/register",
		RequestsPerMinute: 5,
		IdentifierFunc:    sharedMiddleware.GetIPIdentifier,
		KeyPrefix:         "register",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/auth/forgot-password",
		RequestsPerMinute: 5,
		IdentifierFunc:    sharedMiddleware.GetIPIdentifier,
		KeyPrefix:         "forgot_password",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/auth/reset-password",
		RequestsPerMinute: 10,
		IdentifierFunc:    sharedMiddleware.GetIPIdentifier,
		KeyPrefix:         "reset_password",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/auth/check-user",
		RequestsPerMinute: 10,
		IdentifierFunc:    sharedMiddleware.GetIPIdentifier,
		KeyPrefix:         "check_user",
	})

	// === OCR/AI ENDPOINTS (Gemini API Cost Protection) ===
	// These use Gemini AI which has cost implications

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/sales/ocr/batch/sessions",
		RequestsPerMinute: 5,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "ocr_session",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/sales/ocr/batch/deduplicate",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "ocr_dedup",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/sales/ocr/batch/import",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "ocr_import",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/sales/ocr/brands/match",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "ocr_brand_match",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/sales/ocr/brands/create",
		RequestsPerMinute: 5,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "ocr_brand_create",
	})

	// === FINANCE REPORTS (Heavy DB Queries) ===

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/finance/reports/profit-loss",
		RequestsPerMinute: 5,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "finance_pl",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/finance/reports/cash-flow",
		RequestsPerMinute: 5,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "finance_cf",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/finance/reports/balance-sheet",
		RequestsPerMinute: 5,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "finance_bs",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/finance/reports/expense-summary",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "finance_expense",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/finance/reports/vendor-aging",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "finance_vendor",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/finance/dashboard/summary",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "finance_dashboard",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/finance/matrix/dashboard",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "finance_matrix",
	})

	// === BULK OPERATIONS ===

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/notifications/send-bulk",
		RequestsPerMinute: 5,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "bulk_notify",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/super-admin/brands/bulk",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "bulk_brands",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/finance/cash/admin/bulk-reset",
		RequestsPerMinute: 5,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "bulk_cash_reset",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/export",
		RequestsPerMinute: 5,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "export",
	})

	// === INVENTORY OPERATIONS ===

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/inventory/brands/with-variants",
		RequestsPerMinute: 5,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "brand_variants",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/inventory/reports/stock",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "stock_report",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/inventory/reports/movement",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "movement_report",
	})

	// === DASHBOARD ENDPOINTS ===

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/sales/dashboard/summary",
		RequestsPerMinute: 20,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "sales_dashboard",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/dashboard/summary",
		RequestsPerMinute: 20,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "main_dashboard",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/detection/dashboard",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "detection_dashboard",
	})

	limiter.RegisterEndpointLimit(sharedMiddleware.EndpointLimit{
		Path:              "/api/audit/dashboard",
		RequestsPerMinute: 10,
		IdentifierFunc:    getUserIDOrIP,
		KeyPrefix:         "audit_dashboard",
	})
}

// getUserIDOrIP returns user_id if authenticated, otherwise IP
func getUserIDOrIP(c *gin.Context) string {
	if userID := c.GetString("user_id"); userID != "" {
		return "user:" + userID
	}
	return "ip:" + c.ClientIP()
}

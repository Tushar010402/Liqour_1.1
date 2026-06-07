package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// v1.0.231 — shared tenant-ID parser for Smart Purchase handlers.
//
// REGRESSION FIX: Pre-v1.0.231 every Smart Purchase handler did
// `tenantIDRaw.(uuid.UUID)`. But the inventory service's middleware stores
// `tenant_id` in gin context as a STRING (read from the `X-Tenant-ID` header
// the gateway sets after JWT decode — JWT claims serialise UUIDs as strings).
// The type assertion to `uuid.UUID` ALWAYS failed → 500 "Invalid tenant ID".
//
// chhotu's "Batch disambig failed: 500" symptom was this bug — every Purcha
// gate upload returned 500 even when the photo + queries were valid, because
// the handler 500ed before reaching ResolveDisambigBatchMulti. All bad logic
// downstream (the v230 zero-brand → 422 fix) couldn't help because the
// request never got that far. nginx access log showed `500 53` consistently
// because the response was always the same fixed-shape body.
//
// Same bug existed in apply / vendor / replay handlers (silent because chhotu
// hadn't reached those steps yet — disambig blocks progression to apply).
//
// This helper parses the string value to a uuid.UUID, mirroring the pattern
// already used in alias_hygiene_handler.go / brand_creation_handlers.go /
// smart_stock_setup_handler.go (which all worked correctly).
type tenantContextError struct {
	status int
	msg    string
}

func (e *tenantContextError) Error() string { return e.msg }

// tenantUUIDFromContext reads `tenant_id` from gin context, type-asserts to
// string (the shape the middleware stores), parses to uuid.UUID, and returns
// it. On any failure returns the appropriate HTTP-status hint so callers can
// fail with the right status code.
func tenantUUIDFromContext(c *gin.Context) (uuid.UUID, *tenantContextError) {
	raw, exists := c.Get("tenant_id")
	if !exists {
		return uuid.Nil, &tenantContextError{status: http.StatusUnauthorized, msg: "Tenant ID not found"}
	}
	s, ok := raw.(string)
	if !ok {
		// Defensive — if a future middleware stores a non-string here we
		// surface the type problem instead of silently failing.
		return uuid.Nil, &tenantContextError{status: http.StatusInternalServerError, msg: "Invalid tenant ID type"}
	}
	id, err := uuid.Parse(s)
	if err != nil || id == uuid.Nil {
		return uuid.Nil, &tenantContextError{status: http.StatusInternalServerError, msg: "Invalid tenant ID format"}
	}
	return id, nil
}

// userUUIDFromContext is the same idea for `user_id`.
func userUUIDFromContext(c *gin.Context) (uuid.UUID, *tenantContextError) {
	raw, exists := c.Get("user_id")
	if !exists {
		return uuid.Nil, &tenantContextError{status: http.StatusUnauthorized, msg: "User ID not found"}
	}
	s, ok := raw.(string)
	if !ok {
		return uuid.Nil, &tenantContextError{status: http.StatusInternalServerError, msg: "Invalid user ID type"}
	}
	id, err := uuid.Parse(s)
	if err != nil || id == uuid.Nil {
		return uuid.Nil, &tenantContextError{status: http.StatusInternalServerError, msg: "Invalid user ID format"}
	}
	return id, nil
}

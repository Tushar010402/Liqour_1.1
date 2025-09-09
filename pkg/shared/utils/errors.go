package utils

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
)

// ErrorResponse represents a standardized error response
type ErrorResponse struct {
	Error   string                 `json:"error"`
	Code    string                 `json:"code,omitempty"`
	Details map[string]interface{} `json:"details,omitempty"`
	TraceID string                 `json:"trace_id,omitempty"`
}

// ValidationErrorResponse represents validation error details
type ValidationErrorResponse struct {
	Error   string                     `json:"error"`
	Code    string                     `json:"code"`
	Fields  map[string][]string        `json:"fields,omitempty"`
	Details map[string]interface{}     `json:"details,omitempty"`
	TraceID string                     `json:"trace_id,omitempty"`
}

// StandardErrorCodes defines common error codes
const (
	ErrCodeValidation       = "VALIDATION_ERROR"
	ErrCodeUnauthorized     = "UNAUTHORIZED"
	ErrCodeForbidden        = "FORBIDDEN"
	ErrCodeNotFound         = "NOT_FOUND"
	ErrCodeConflict         = "CONFLICT"
	ErrCodeInternal         = "INTERNAL_ERROR"
	ErrCodeBadRequest       = "BAD_REQUEST"
	ErrCodeServiceUnavailable = "SERVICE_UNAVAILABLE"
	ErrCodeTimeout          = "TIMEOUT"
	ErrCodeRateLimited      = "RATE_LIMITED"
	ErrCodeInvalidToken     = "INVALID_TOKEN"
	ErrCodeExpiredToken     = "EXPIRED_TOKEN"
	ErrCodeTenantMismatch   = "TENANT_MISMATCH"
	ErrCodeInsufficientRole = "INSUFFICIENT_ROLE"
)

// HandleError sends a standardized error response
func HandleError(c *gin.Context, statusCode int, errorCode string, message string, details ...map[string]interface{}) {
	response := ErrorResponse{
		Error:   message,
		Code:    errorCode,
		TraceID: c.GetString("request_id"),
	}

	if len(details) > 0 {
		response.Details = details[0]
	}

	c.JSON(statusCode, response)
}

// HandleValidationError processes validation errors and sends formatted response
func HandleValidationError(c *gin.Context, err error) {
	var validationErrors validator.ValidationErrors
	fields := make(map[string][]string)

	if errs, ok := err.(validator.ValidationErrors); ok {
		validationErrors = errs
		for _, e := range validationErrors {
			field := ToSnakeCase(e.Field())
			message := getValidationMessage(e)
			fields[field] = append(fields[field], message)
		}
	}

	response := ValidationErrorResponse{
		Error:   "Validation failed",
		Code:    ErrCodeValidation,
		Fields:  fields,
		TraceID: c.GetString("request_id"),
	}

	c.JSON(http.StatusBadRequest, response)
}

// HandleNotFound sends a standardized not found error
func HandleNotFound(c *gin.Context, resource string) {
	HandleError(c, http.StatusNotFound, ErrCodeNotFound, 
		fmt.Sprintf("%s not found", resource),
		map[string]interface{}{"resource": resource})
}

// HandleUnauthorized sends a standardized unauthorized error
func HandleUnauthorized(c *gin.Context, message string) {
	if message == "" {
		message = "Unauthorized access"
	}
	HandleError(c, http.StatusUnauthorized, ErrCodeUnauthorized, message)
}

// HandleForbidden sends a standardized forbidden error
func HandleForbidden(c *gin.Context, message string) {
	if message == "" {
		message = "Access forbidden"
	}
	HandleError(c, http.StatusForbidden, ErrCodeForbidden, message)
}

// HandleConflict sends a standardized conflict error
func HandleConflict(c *gin.Context, message string, details ...map[string]interface{}) {
	HandleError(c, http.StatusConflict, ErrCodeConflict, message, details...)
}

// HandleInternalError sends a standardized internal error
func HandleInternalError(c *gin.Context, message string) {
	// Log the actual error internally but send generic message to client
	HandleError(c, http.StatusInternalServerError, ErrCodeInternal, 
		"An internal error occurred. Please try again later.")
}

// HandleServiceUnavailable sends a standardized service unavailable error
func HandleServiceUnavailable(c *gin.Context, service string) {
	HandleError(c, http.StatusServiceUnavailable, ErrCodeServiceUnavailable,
		fmt.Sprintf("%s service is currently unavailable", service),
		map[string]interface{}{"service": service})
}

// HandleBadRequest sends a standardized bad request error
func HandleBadRequest(c *gin.Context, message string, details ...map[string]interface{}) {
	HandleError(c, http.StatusBadRequest, ErrCodeBadRequest, message, details...)
}

// getValidationMessage returns user-friendly validation messages
func getValidationMessage(e validator.FieldError) string {
	field := e.Field()
	tag := e.Tag()
	param := e.Param()

	switch tag {
	case "required":
		return fmt.Sprintf("%s is required", field)
	case "min":
		return fmt.Sprintf("%s must be at least %s characters", field, param)
	case "max":
		return fmt.Sprintf("%s must be at most %s characters", field, param)
	case "email":
		return fmt.Sprintf("%s must be a valid email address", field)
	case "gt":
		return fmt.Sprintf("%s must be greater than %s", field, param)
	case "gte":
		return fmt.Sprintf("%s must be greater than or equal to %s", field, param)
	case "lt":
		return fmt.Sprintf("%s must be less than %s", field, param)
	case "lte":
		return fmt.Sprintf("%s must be less than or equal to %s", field, param)
	case "uuid":
		return fmt.Sprintf("%s must be a valid UUID", field)
	case "alpha":
		return fmt.Sprintf("%s must contain only letters", field)
	case "alphanum":
		return fmt.Sprintf("%s must contain only letters and numbers", field)
	case "numeric":
		return fmt.Sprintf("%s must be a number", field)
	case "oneof":
		return fmt.Sprintf("%s must be one of: %s", field, param)
	default:
		return fmt.Sprintf("%s validation failed on %s constraint", field, tag)
	}
}

// ToSnakeCase converts a string to snake_case
func ToSnakeCase(str string) string {
	var result strings.Builder
	for i, r := range str {
		if i > 0 && r >= 'A' && r <= 'Z' {
			result.WriteRune('_')
		}
		result.WriteRune(r)
	}
	return strings.ToLower(result.String())
}

// WrapDatabaseError converts database errors to user-friendly messages
func WrapDatabaseError(c *gin.Context, err error, operation string) {
	errStr := err.Error()
	
	switch {
	case strings.Contains(errStr, "duplicate key"):
		HandleConflict(c, "Resource already exists", map[string]interface{}{
			"operation": operation,
		})
	case strings.Contains(errStr, "foreign key constraint"):
		HandleBadRequest(c, "Referenced resource does not exist or cannot be deleted due to existing references")
	case strings.Contains(errStr, "not found"):
		HandleNotFound(c, operation)
	default:
		HandleInternalError(c, fmt.Sprintf("Database operation failed: %s", operation))
	}
}

// Success sends a standardized success response
func Success(c *gin.Context, statusCode int, data interface{}, message ...string) {
	response := gin.H{
		"success": true,
		"data":    data,
	}
	
	if len(message) > 0 && message[0] != "" {
		response["message"] = message[0]
	}
	
	if requestID := c.GetString("request_id"); requestID != "" {
		response["trace_id"] = requestID
	}
	
	c.JSON(statusCode, response)
}

// SuccessWithPagination sends a paginated success response
func SuccessWithPagination(c *gin.Context, data interface{}, total int64, page int, pageSize int) {
	totalPages := (total + int64(pageSize) - 1) / int64(pageSize)
	
	response := gin.H{
		"success": true,
		"data":    data,
		"pagination": gin.H{
			"total":       total,
			"page":        page,
			"page_size":   pageSize,
			"total_pages": totalPages,
		},
	}
	
	if requestID := c.GetString("request_id"); requestID != "" {
		response["trace_id"] = requestID
	}
	
	c.JSON(http.StatusOK, response)
}
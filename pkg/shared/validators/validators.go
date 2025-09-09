package validators

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// ValidationError represents a validation error
type ValidationError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

func (e ValidationError) Error() string {
	return fmt.Sprintf("%s: %s", e.Field, e.Message)
}

// ValidationErrors is a slice of validation errors
type ValidationErrors []ValidationError

func (e ValidationErrors) Error() string {
	messages := make([]string, len(e))
	for i, err := range e {
		messages[i] = err.Error()
	}
	return strings.Join(messages, "; ")
}

// Validator provides validation functions
type Validator struct {
	errors ValidationErrors
}

// New creates a new validator instance
func New() *Validator {
	return &Validator{
		errors: make(ValidationErrors, 0),
	}
}

// AddError adds a validation error
func (v *Validator) AddError(field, message string) {
	v.errors = append(v.errors, ValidationError{
		Field:   field,
		Message: message,
	})
}

// HasErrors returns true if there are validation errors
func (v *Validator) HasErrors() bool {
	return len(v.errors) > 0
}

// Errors returns all validation errors
func (v *Validator) Errors() ValidationErrors {
	return v.errors
}

// Clear clears all validation errors
func (v *Validator) Clear() {
	v.errors = make(ValidationErrors, 0)
}

// Required validates that a field is not empty
func (v *Validator) Required(value interface{}, field string) {
	switch val := value.(type) {
	case string:
		if strings.TrimSpace(val) == "" {
			v.AddError(field, "is required")
		}
	case int:
		if val == 0 {
			v.AddError(field, "is required")
		}
	case int64:
		if val == 0 {
			v.AddError(field, "is required")
		}
	case float64:
		if val == 0 {
			v.AddError(field, "is required")
		}
	case uuid.UUID:
		if val == uuid.Nil {
			v.AddError(field, "is required")
		}
	case *string:
		if val == nil || strings.TrimSpace(*val) == "" {
			v.AddError(field, "is required")
		}
	case *int:
		if val == nil || *val == 0 {
			v.AddError(field, "is required")
		}
	case *float64:
		if val == nil || *val == 0 {
			v.AddError(field, "is required")
		}
	default:
		if value == nil {
			v.AddError(field, "is required")
		}
	}
}

// Email validates email format
func (v *Validator) Email(email, field string) {
	if email == "" {
		return // Skip validation for empty values
	}
	
	emailRegex := regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)
	if !emailRegex.MatchString(email) {
		v.AddError(field, "must be a valid email address")
	}
}

// Phone validates phone number format
func (v *Validator) Phone(phone, field string) {
	if phone == "" {
		return // Skip validation for empty values
	}
	
	phoneRegex := regexp.MustCompile(`^[+]?[\d\s\-\(\)]{10,15}$`)
	if !phoneRegex.MatchString(phone) {
		v.AddError(field, "must be a valid phone number")
	}
}

// MinLength validates minimum string length
func (v *Validator) MinLength(value string, min int, field string) {
	if value == "" {
		return // Skip validation for empty values
	}
	
	if len(value) < min {
		v.AddError(field, fmt.Sprintf("must be at least %d characters long", min))
	}
}

// MaxLength validates maximum string length
func (v *Validator) MaxLength(value string, max int, field string) {
	if len(value) > max {
		v.AddError(field, fmt.Sprintf("must not exceed %d characters", max))
	}
}

// Min validates minimum numeric value
func (v *Validator) Min(value interface{}, min float64, field string) {
	var val float64
	
	switch vt := value.(type) {
	case int:
		val = float64(vt)
	case int64:
		val = float64(vt)
	case float64:
		val = vt
	case string:
		var err error
		val, err = strconv.ParseFloat(vt, 64)
		if err != nil {
			v.AddError(field, "must be a valid number")
			return
		}
	default:
		v.AddError(field, "must be a numeric value")
		return
	}
	
	if val < min {
		v.AddError(field, fmt.Sprintf("must be at least %.2f", min))
	}
}

// Max validates maximum numeric value
func (v *Validator) Max(value interface{}, max float64, field string) {
	var val float64
	
	switch vt := value.(type) {
	case int:
		val = float64(vt)
	case int64:
		val = float64(vt)
	case float64:
		val = vt
	case string:
		var err error
		val, err = strconv.ParseFloat(vt, 64)
		if err != nil {
			v.AddError(field, "must be a valid number")
			return
		}
	default:
		v.AddError(field, "must be a numeric value")
		return
	}
	
	if val > max {
		v.AddError(field, fmt.Sprintf("must not exceed %.2f", max))
	}
}

// Positive validates that a numeric value is positive
func (v *Validator) Positive(value interface{}, field string) {
	v.Min(value, 0.01, field)
}

// NonNegative validates that a numeric value is not negative
func (v *Validator) NonNegative(value interface{}, field string) {
	v.Min(value, 0, field)
}

// In validates that a value is in a given slice
func (v *Validator) In(value string, options []string, field string) {
	if value == "" {
		return // Skip validation for empty values
	}
	
	for _, option := range options {
		if value == option {
			return
		}
	}
	
	v.AddError(field, fmt.Sprintf("must be one of: %s", strings.Join(options, ", ")))
}

// UUID validates UUID format
func (v *Validator) UUID(value string, field string) {
	if value == "" {
		return // Skip validation for empty values
	}
	
	if _, err := uuid.Parse(value); err != nil {
		v.AddError(field, "must be a valid UUID")
	}
}

// Date validates date format (YYYY-MM-DD)
func (v *Validator) Date(value string, field string) {
	if value == "" {
		return // Skip validation for empty values
	}
	
	if _, err := time.Parse("2006-01-02", value); err != nil {
		v.AddError(field, "must be a valid date (YYYY-MM-DD)")
	}
}

// DateTime validates datetime format
func (v *Validator) DateTime(value string, field string) {
	if value == "" {
		return // Skip validation for empty values
	}
	
	if _, err := time.Parse("2006-01-02T15:04:05Z", value); err != nil {
		if _, err := time.Parse("2006-01-02 15:04:05", value); err != nil {
			v.AddError(field, "must be a valid datetime")
		}
	}
}

// Password validates password strength
func (v *Validator) Password(password, field string) {
	if password == "" {
		return // Required validation should be done separately
	}
	
	if len(password) < 8 {
		v.AddError(field, "must be at least 8 characters long")
	}
	
	hasUpper := regexp.MustCompile(`[A-Z]`).MatchString(password)
	hasLower := regexp.MustCompile(`[a-z]`).MatchString(password)
	hasDigit := regexp.MustCompile(`\d`).MatchString(password)
	hasSpecial := regexp.MustCompile(`[^a-zA-Z0-9]`).MatchString(password)
	
	if !hasUpper {
		v.AddError(field, "must contain at least one uppercase letter")
	}
	if !hasLower {
		v.AddError(field, "must contain at least one lowercase letter")
	}
	if !hasDigit {
		v.AddError(field, "must contain at least one digit")
	}
	if !hasSpecial {
		v.AddError(field, "must contain at least one special character")
	}
}

// PasswordMatch validates that two passwords match
func (v *Validator) PasswordMatch(password, confirmPassword, field string) {
	if password != confirmPassword {
		v.AddError(field, "passwords do not match")
	}
}

// BusinessValidations contains domain-specific validations

// ValidRole validates user role
func (v *Validator) ValidRole(role, field string) {
	validRoles := []string{"admin", "manager", "executive", "salesman", "assistant_manager", "saas_admin"}
	v.In(role, validRoles, field)
}

// ValidPaymentMethod validates payment method
func (v *Validator) ValidPaymentMethod(method, field string) {
	validMethods := []string{"cash", "card", "upi", "credit"}
	v.In(method, validMethods, field)
}

// ValidStatus validates status fields
func (v *Validator) ValidStatus(status, field string) {
	validStatuses := []string{"pending", "approved", "rejected", "active", "inactive"}
	v.In(status, validStatuses, field)
}

// ValidCostingMethod validates stock costing method
func (v *Validator) ValidCostingMethod(method, field string) {
	validMethods := []string{"fifo", "lifo", "average"}
	v.In(method, validMethods, field)
}
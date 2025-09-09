package utils

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

// Password utilities
func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(bytes), err
}

func CheckPassword(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

// String utilities
func GenerateRandomString(length int) (string, error) {
	bytes := make([]byte, length/2)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

func IsValidEmail(email string) bool {
	emailRegex := regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)
	return emailRegex.MatchString(email)
}

func IsValidPhone(phone string) bool {
	phoneRegex := regexp.MustCompile(`^[+]?[\d\s\-\(\)]{10,15}$`)
	return phoneRegex.MatchString(phone)
}

func SanitizeString(input string) string {
	return strings.TrimSpace(input)
}

func TruncateString(input string, length int) string {
	if len(input) <= length {
		return input
	}
	return input[:length] + "..."
}

// Number utilities
func ParseFloat(s string) (float64, error) {
	return strconv.ParseFloat(s, 64)
}

func ParseInt(s string) (int, error) {
	return strconv.Atoi(s)
}

func FormatCurrency(amount float64) string {
	return fmt.Sprintf("₹%.2f", amount)
}

func RoundToTwoDecimals(amount float64) float64 {
	return float64(int(amount*100)) / 100
}

// Date utilities
func FormatDate(t time.Time) string {
	return t.Format("2006-01-02")
}

func FormatDateTime(t time.Time) string {
	return t.Format("2006-01-02 15:04:05")
}

func ParseDate(dateStr string) (time.Time, error) {
	return time.Parse("2006-01-02", dateStr)
}

func ParseDateTime(dateTimeStr string) (time.Time, error) {
	return time.Parse("2006-01-02 15:04:05", dateTimeStr)
}

func StartOfDay(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}

func EndOfDay(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 23, 59, 59, 999999999, t.Location())
}

func IsToday(t time.Time) bool {
	now := time.Now()
	return t.Year() == now.Year() && t.Month() == now.Month() && t.Day() == now.Day()
}

func DaysAgo(days int) time.Time {
	return time.Now().AddDate(0, 0, -days)
}

// Business utilities
func GenerateSaleNumber() string {
	now := time.Now()
	timestamp := now.Format("20060102150405")
	randomPart, _ := GenerateRandomString(4)
	return fmt.Sprintf("SALE-%s-%s", timestamp, strings.ToUpper(randomPart))
}

func GenerateReturnNumber() string {
	now := time.Now()
	timestamp := now.Format("20060102150405")
	randomPart, _ := GenerateRandomString(4)
	return fmt.Sprintf("RET-%s-%s", timestamp, strings.ToUpper(randomPart))
}

func GeneratePurchaseNumber() string {
	now := time.Now()
	timestamp := now.Format("20060102150405")
	randomPart, _ := GenerateRandomString(4)
	return fmt.Sprintf("PUR-%s-%s", timestamp, strings.ToUpper(randomPart))
}

func GenerateEmployeeID() string {
	now := time.Now()
	year := now.Format("2006")
	randomPart, _ := GenerateRandomString(6)
	return fmt.Sprintf("EMP%s%s", year, strings.ToUpper(randomPart))
}

// Validation utilities
func ValidateRequired(value interface{}, fieldName string) error {
	switch v := value.(type) {
	case string:
		if strings.TrimSpace(v) == "" {
			return fmt.Errorf("%s is required", fieldName)
		}
	case int:
		if v == 0 {
			return fmt.Errorf("%s is required", fieldName)
		}
	case float64:
		if v == 0 {
			return fmt.Errorf("%s is required", fieldName)
		}
	case uuid.UUID:
		if v == uuid.Nil {
			return fmt.Errorf("%s is required", fieldName)
		}
	}
	return nil
}

func ValidatePositiveAmount(amount float64, fieldName string) error {
	if amount <= 0 {
		return fmt.Errorf("%s must be greater than 0", fieldName)
	}
	return nil
}

func ValidateQuantity(quantity int, fieldName string) error {
	if quantity <= 0 {
		return fmt.Errorf("%s must be greater than 0", fieldName)
	}
	return nil
}

// Slice utilities
func Contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

func ContainsInt(slice []int, item int) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

func Remove(slice []string, item string) []string {
	var result []string
	for _, s := range slice {
		if s != item {
			result = append(result, s)
		}
	}
	return result
}

func Unique(slice []string) []string {
	keys := make(map[string]bool)
	var result []string
	for _, s := range slice {
		if !keys[s] {
			keys[s] = true
			result = append(result, s)
		}
	}
	return result
}

// Math utilities
func Max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func Min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func MaxFloat(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func MinFloat(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}

func Abs(a int) int {
	if a < 0 {
		return -a
	}
	return a
}

func AbsFloat(a float64) float64 {
	if a < 0 {
		return -a
	}
	return a
}
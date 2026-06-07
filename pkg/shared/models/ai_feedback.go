package models

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// AIFeedback stores user feedback on AI-powered features with full context for UX analysis
type AIFeedback struct {
	ID              uuid.UUID      `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID        uuid.UUID      `json:"tenant_id" gorm:"type:uuid;index;not null"`
	UserID          uuid.UUID      `json:"user_id" gorm:"type:uuid;index;not null"`
	FlowType        string         `json:"flow_type" gorm:"type:varchar(50);not null;index"`  // "stock_setup", "daily_sales", "purchase_entry"
	Rating          int            `json:"rating" gorm:"not null"`                              // 1-5
	Tags            JSONStringList `json:"tags" gorm:"type:jsonb;default:'[]'"`
	Comment         *string        `json:"comment,omitempty"`
	AppVersion      string         `json:"app_version" gorm:"type:varchar(20);default:''"`     // e.g. "1.2.0"
	Platform        string         `json:"platform" gorm:"type:varchar(10);default:''"`        // "ios" or "android"
	DeviceModel     string         `json:"device_model" gorm:"type:varchar(100);default:''"`   // e.g. "iPhone 15 Pro", "SM-S918B"
	ScreenName      string         `json:"screen_name" gorm:"type:varchar(100);default:''"`    // which screen feedback was given from
	SessionDuration *int           `json:"session_duration,omitempty"`                          // seconds spent in the flow before feedback
	ItemsProcessed  *int           `json:"items_processed,omitempty"`                          // how many items were in the AI flow
	Metadata        JSONMap        `json:"metadata,omitempty" gorm:"type:jsonb;default:'{}'"` // extra context (error messages, retry count, etc.)
	CreatedAt       time.Time      `json:"created_at" gorm:"autoCreateTime"`
	DeletedAt       gorm.DeletedAt `json:"deleted_at,omitempty" gorm:"index"`
}

// JSONStringList implements Scanner/Valuer for GORM JSONB string arrays
type JSONStringList []string

func (j JSONStringList) Value() (driver.Value, error) {
	if j == nil {
		return "[]", nil
	}
	b, err := json.Marshal(j)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal JSONStringList: %w", err)
	}
	return string(b), nil
}

func (j *JSONStringList) Scan(value interface{}) error {
	if value == nil {
		*j = JSONStringList{}
		return nil
	}
	var bytes []byte
	switch v := value.(type) {
	case string:
		bytes = []byte(v)
	case []byte:
		bytes = v
	default:
		return fmt.Errorf("unsupported type for JSONStringList: %T", value)
	}
	return json.Unmarshal(bytes, j)
}

// JSONMap implements Scanner/Valuer for GORM JSONB maps
type JSONMap map[string]interface{}

func (j JSONMap) Value() (driver.Value, error) {
	if j == nil {
		return "{}", nil
	}
	b, err := json.Marshal(j)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal JSONMap: %w", err)
	}
	return string(b), nil
}

func (j *JSONMap) Scan(value interface{}) error {
	if value == nil {
		*j = JSONMap{}
		return nil
	}
	var bytes []byte
	switch v := value.(type) {
	case string:
		bytes = []byte(v)
	case []byte:
		bytes = v
	default:
		return fmt.Errorf("unsupported type for JSONMap: %T", value)
	}
	return json.Unmarshal(bytes, j)
}

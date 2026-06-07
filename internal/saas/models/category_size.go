package models

import (
	"github.com/google/uuid"
	"gorm.io/gorm"
)

// CategorySize represents a size option for a specific category
type CategorySize struct {
	ID          uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	CategoryID  uuid.UUID      `json:"category_id" gorm:"type:uuid;not null;index"`
	SizeName    string         `json:"size_name" gorm:"type:varchar(50);not null"` // e.g., "330ml", "750ml"
	DisplayName string         `json:"display_name" gorm:"type:varchar(100)"`       // e.g., "330ml - Small Bottle"
	SortOrder   int            `json:"sort_order" gorm:"default:0"`
	IsActive    bool           `json:"is_active" gorm:"default:true"`
	CreatedAt   int64          `json:"created_at" gorm:"autoCreateTime:milli"`
	UpdatedAt   int64          `json:"updated_at" gorm:"autoUpdateTime:milli"`
	DeletedAt   gorm.DeletedAt `json:"deleted_at,omitempty" gorm:"index"`
}

// TableName specifies the table name for CategorySize
func (CategorySize) TableName() string {
	return "category_sizes"
}

package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// FeatureFlag represents a feature flag for controlling features
type FeatureFlag struct {
	ID                uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	Name              string         `json:"name" gorm:"not null"`
	Key               string         `json:"key" gorm:"uniqueIndex;not null"`
	Description       string         `json:"description"`
	Enabled           bool           `json:"enabled" gorm:"default:false"`
	RolloutPercentage int            `json:"rollout_percentage" gorm:"default:0"`
	TargetTenants     string         `json:"target_tenants" gorm:"type:text"` // JSON array of tenant IDs
	Metadata          string         `json:"metadata" gorm:"type:text"`       // JSON
	CreatedAt         time.Time      `json:"created_at"`
	UpdatedAt         time.Time      `json:"updated_at"`
	DeletedAt         gorm.DeletedAt `json:"deleted_at" gorm:"index"`
}

// SystemConfiguration represents system-level configuration
type SystemConfiguration struct {
	ID          uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	Key         string         `json:"key" gorm:"uniqueIndex;not null"`
	Value       string         `json:"value" gorm:"type:text"`
	ValueType   string         `json:"value_type" gorm:"not null;default:'string'"` // string, int, bool, json
	Category    string         `json:"category" gorm:"index"`
	Description string         `json:"description"`
	IsSecret    bool           `json:"is_secret" gorm:"default:false"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `json:"deleted_at" gorm:"index"`
}

type CreateFeatureFlagRequest struct {
	Name              string `json:"name" binding:"required"`
	Key               string `json:"key" binding:"required"`
	Description       string `json:"description"`
	Enabled           bool   `json:"enabled"`
	RolloutPercentage int    `json:"rollout_percentage"`
	TargetTenants     string `json:"target_tenants"`
	Metadata          string `json:"metadata"`
}

type UpdateFeatureFlagRequest struct {
	Name              *string `json:"name"`
	Description       *string `json:"description"`
	Enabled           *bool   `json:"enabled"`
	RolloutPercentage *int    `json:"rollout_percentage"`
	TargetTenants     *string `json:"target_tenants"`
	Metadata          *string `json:"metadata"`
}

type UpdateConfigRequest struct {
	Value       string `json:"value" binding:"required"`
	Description string `json:"description"`
}

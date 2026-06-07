package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// Unit represents a measurement unit (ml, L, cl, etc.)
type Unit struct {
	ID               uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	Name             string         `json:"name" gorm:"not null"`
	Symbol           string         `json:"symbol" gorm:"not null;uniqueIndex"`
	UnitType         string         `json:"unit_type" gorm:"not null;index"` // volume, weight, count
	ConversionFactor float64        `json:"conversion_factor" gorm:"not null;default:1"` // relative to base unit (ml for volume)
	IsActive         bool           `json:"is_active" gorm:"default:true"`
	SortOrder        int            `json:"sort_order" gorm:"default:0"`
	CreatedAt        time.Time      `json:"created_at"`
	UpdatedAt        time.Time      `json:"updated_at"`
	DeletedAt        gorm.DeletedAt `json:"deleted_at" gorm:"index"`
}

type CreateUnitRequest struct {
	Name             string  `json:"name" binding:"required"`
	Symbol           string  `json:"symbol" binding:"required"`
	UnitType         string  `json:"unit_type" binding:"required,oneof=volume weight count"`
	ConversionFactor float64 `json:"conversion_factor" binding:"required,gt=0"`
	SortOrder        int     `json:"sort_order"`
}

type UpdateUnitRequest struct {
	Name             *string  `json:"name"`
	Symbol           *string  `json:"symbol"`
	UnitType         *string  `json:"unit_type" binding:"omitempty,oneof=volume weight count"`
	ConversionFactor *float64 `json:"conversion_factor" binding:"omitempty,gt=0"`
	IsActive         *bool    `json:"is_active"`
	SortOrder        *int     `json:"sort_order"`
}

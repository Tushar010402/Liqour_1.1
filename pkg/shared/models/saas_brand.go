package models

import (
	"github.com/google/uuid"
)

// SaaSBrand represents a global brand in the SaaS catalog
type SaaSBrand struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
}

// SaaSBrandVariant represents a variant of a SaaS brand
type SaaSBrandVariant struct {
	ID      uuid.UUID `json:"id"`
	BrandID uuid.UUID `json:"brand_id"`
	Name    string    `json:"name"`
	Size    string    `json:"size"`
}

// MasterBrandInfo is a read-only view of brand_variants + saas_brands for AI matching
type MasterBrandInfo struct {
	VariantID             string  `json:"variant_id" gorm:"column:variant_id"`
	BrandID               string  `json:"brand_id" gorm:"column:brand_id"`
	BrandName             string  `json:"brand_name" gorm:"column:brand_name"`
	DisplayName           string  `json:"display_name" gorm:"column:display_name"`
	DisplayNameBoldStart  *int    `json:"display_name_bold_start,omitempty" gorm:"column:display_name_bold_start"`
	DisplayNameBoldLength *int    `json:"display_name_bold_length,omitempty" gorm:"column:display_name_bold_length"`
	Size                  string  `json:"size" gorm:"column:size"`
	MRP                   float64 `json:"mrp" gorm:"column:mrp"`
	Category              string  `json:"category" gorm:"column:category"`
	CategoryID            string  `json:"category_id" gorm:"column:category_id"`
	SubType               string  `json:"sub_type" gorm:"column:sub_type"`
	State                 string  `json:"state" gorm:"column:state"`
	// v1.0.202 — pipe-delimited meta_keywords from saas_brands. Loaded by
	// loadMasterBrands and consumed by scoreMasterBrand so the Add Missing
	// search ranks brands whose synonyms contain the OCR text alongside the
	// canonical name. Concrete win: typing "MCD" or "Mc D" surfaces "Mc
	// Dowells No1 ORIGINAL BLENDED" because that brand's meta_keywords list
	// includes "MCD" / "Mc D" — without this, a 3-char query rejected by the
	// 0.35 score threshold dropped through to alphabetical substring fallback.
	// Pipe is the delimiter (not comma) because meta_keywords entries can
	// themselves contain commas.
	MetaKeywordsCSV string `json:"-" gorm:"column:meta_keywords_csv"`
}

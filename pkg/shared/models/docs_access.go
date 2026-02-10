package models

import (
	"time"

	"github.com/google/uuid"
)

// DocsAccessRole defines the access level for documentation
type DocsAccessRole string

const (
	DocsRoleViewer DocsAccessRole = "viewer" // Can view and comment
	DocsRoleEditor DocsAccessRole = "editor" // Can view, comment, and edit
)

// DocsAccess represents user access to documentation system
type DocsAccess struct {
	BaseModel
	UserID      uuid.UUID      `json:"user_id" gorm:"type:uuid;not null;uniqueIndex"`
	User        *User          `json:"user,omitempty" gorm:"foreignKey:UserID"`
	Role        DocsAccessRole `json:"role" gorm:"type:varchar(20);not null;default:'viewer'"`
	GrantedByID uuid.UUID      `json:"granted_by_id" gorm:"type:uuid;not null"`
	GrantedBy   *User          `json:"granted_by,omitempty" gorm:"foreignKey:GrantedByID"`
	ExpiresAt   *time.Time     `json:"expires_at,omitempty"`
	IsActive    bool           `json:"is_active" gorm:"default:true"`
	Notes       string         `json:"notes,omitempty" gorm:"type:text"`
}

// TableName returns the table name
func (DocsAccess) TableName() string {
	return "docs_access"
}

// DocsComment represents a comment on documentation
type DocsComment struct {
	BaseModel
	PageID         string     `json:"page_id" gorm:"type:varchar(255);not null;index"`
	PagePath       string     `json:"page_path,omitempty" gorm:"type:varchar(500)"`
	UserID         uuid.UUID  `json:"user_id" gorm:"type:uuid;not null;index"`
	User           *User      `json:"user,omitempty" gorm:"foreignKey:UserID"`
	Content        string     `json:"content" gorm:"type:text;not null"`
	Selection      string     `json:"selection,omitempty" gorm:"type:text"`
	SelectionXPath string     `json:"selection_xpath,omitempty" gorm:"type:text"`
	StartOffset    int        `json:"start_offset,omitempty"`
	EndOffset      int        `json:"end_offset,omitempty"`
	ParentID       *uuid.UUID `json:"parent_id,omitempty" gorm:"type:uuid;index"`
	Parent         *DocsComment `json:"parent,omitempty" gorm:"foreignKey:ParentID"`
	IsResolved     bool       `json:"is_resolved" gorm:"default:false"`
	ResolvedAt     *time.Time `json:"resolved_at,omitempty"`
	ResolvedByID   *uuid.UUID `json:"resolved_by_id,omitempty" gorm:"type:uuid"`
	ResolvedBy     *User      `json:"resolved_by,omitempty" gorm:"foreignKey:ResolvedByID"`
}

// TableName returns the table name
func (DocsComment) TableName() string {
	return "docs_comments"
}

// DocsEdit represents an edit to documentation
type DocsEdit struct {
	BaseModel
	PageID      string     `json:"page_id" gorm:"type:varchar(255);not null;index"`
	PagePath    string     `json:"page_path,omitempty" gorm:"type:varchar(500)"`
	UserID      uuid.UUID  `json:"user_id" gorm:"type:uuid;not null;index"`
	User        *User      `json:"user,omitempty" gorm:"foreignKey:UserID"`
	FilePath    string     `json:"file_path" gorm:"type:varchar(500);not null"`
	OldContent  string     `json:"old_content,omitempty" gorm:"type:text"`
	NewContent  string     `json:"new_content" gorm:"type:text;not null"`
	DiffPatch   string     `json:"diff_patch,omitempty" gorm:"type:text"`
	Status      string     `json:"status" gorm:"type:varchar(20);default:'approved'"`
	ApprovedByID *uuid.UUID `json:"approved_by_id,omitempty" gorm:"type:uuid"`
	ApprovedBy  *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	ApprovedAt  *time.Time `json:"approved_at,omitempty"`
}

// TableName returns the table name
func (DocsEdit) TableName() string {
	return "docs_edits"
}

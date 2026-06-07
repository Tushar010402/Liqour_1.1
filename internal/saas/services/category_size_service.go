package services

import (
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/saas/models"
	"gorm.io/gorm"
)

// CategorySizeService handles category size operations
type CategorySizeService struct {
	db *gorm.DB
}

// NewCategorySizeService creates a new CategorySizeService
func NewCategorySizeService(db *gorm.DB) *CategorySizeService {
	return &CategorySizeService{db: db}
}

// CreateCategorySizeRequest represents request to create a category size
type CreateCategorySizeRequest struct {
	CategoryID  string `json:"category_id" binding:"required"`
	SizeName    string `json:"size_name" binding:"required"`
	DisplayName string `json:"display_name"`
	SortOrder   int    `json:"sort_order"`
	IsActive    bool   `json:"is_active"`
}

// UpdateCategorySizeRequest represents request to update a category size
type UpdateCategorySizeRequest struct {
	SizeName    string `json:"size_name" binding:"required"`
	DisplayName string `json:"display_name"`
	SortOrder   int    `json:"sort_order"`
	IsActive    bool   `json:"is_active"`
}

// CategorySizeResponse represents category size response
type CategorySizeResponse struct {
	ID          string `json:"id"`
	CategoryID  string `json:"category_id"`
	SizeName    string `json:"size_name"`
	DisplayName string `json:"display_name"`
	SortOrder   int    `json:"sort_order"`
	IsActive    bool   `json:"is_active"`
	CreatedAt   int64  `json:"created_at"`
	UpdatedAt   int64  `json:"updated_at"`
}

// GetAllCategorySizes retrieves all category sizes
func (s *CategorySizeService) GetAllCategorySizes() ([]CategorySizeResponse, error) {
	var sizes []models.CategorySize

	if err := s.db.Where("deleted_at IS NULL").
		Order("category_id, sort_order, size_name").
		Find(&sizes).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch category sizes: %w", err)
	}

	return s.toCategorySizeResponses(sizes), nil
}

// GetCategorySizesByCategory retrieves sizes for a specific category
func (s *CategorySizeService) GetCategorySizesByCategory(categoryID string, activeOnly bool) ([]CategorySizeResponse, error) {
	categoryUUID, err := uuid.Parse(categoryID)
	if err != nil {
		return nil, errors.New("invalid category ID")
	}

	var sizes []models.CategorySize
	query := s.db.Where("category_id = ? AND deleted_at IS NULL", categoryUUID)

	if activeOnly {
		query = query.Where("is_active = ?", true)
	}

	if err := query.Order("sort_order, size_name").Find(&sizes).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch category sizes: %w", err)
	}

	return s.toCategorySizeResponses(sizes), nil
}

// GetCategorySizeByID retrieves a specific category size
func (s *CategorySizeService) GetCategorySizeByID(id string) (*CategorySizeResponse, error) {
	sizeUUID, err := uuid.Parse(id)
	if err != nil {
		return nil, errors.New("invalid size ID")
	}

	var size models.CategorySize
	if err := s.db.Where("id = ? AND deleted_at IS NULL", sizeUUID).First(&size).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("category size not found")
		}
		return nil, fmt.Errorf("failed to fetch category size: %w", err)
	}

	response := s.toCategorySizeResponse(&size)
	return &response, nil
}

// CreateCategorySize creates a new category size
func (s *CategorySizeService) CreateCategorySize(req CreateCategorySizeRequest) (*CategorySizeResponse, error) {
	categoryUUID, err := uuid.Parse(req.CategoryID)
	if err != nil {
		return nil, errors.New("invalid category ID")
	}

	// Check if size already exists for this category
	var existing models.CategorySize
	if err := s.db.Where("category_id = ? AND size_name = ? AND deleted_at IS NULL",
		categoryUUID, req.SizeName).First(&existing).Error; err == nil {
		return nil, errors.New("size already exists for this category")
	}

	size := models.CategorySize{
		CategoryID:  categoryUUID,
		SizeName:    req.SizeName,
		DisplayName: req.DisplayName,
		SortOrder:   req.SortOrder,
		IsActive:    req.IsActive,
	}

	if err := s.db.Create(&size).Error; err != nil {
		return nil, fmt.Errorf("failed to create category size: %w", err)
	}

	response := s.toCategorySizeResponse(&size)
	return &response, nil
}

// UpdateCategorySize updates an existing category size
func (s *CategorySizeService) UpdateCategorySize(id string, req UpdateCategorySizeRequest) (*CategorySizeResponse, error) {
	sizeUUID, err := uuid.Parse(id)
	if err != nil {
		return nil, errors.New("invalid size ID")
	}

	var size models.CategorySize
	if err := s.db.Where("id = ? AND deleted_at IS NULL", sizeUUID).First(&size).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("category size not found")
		}
		return nil, fmt.Errorf("failed to fetch category size: %w", err)
	}

	// Check for duplicate size name in same category
	var existing models.CategorySize
	if err := s.db.Where("category_id = ? AND size_name = ? AND id != ? AND deleted_at IS NULL",
		size.CategoryID, req.SizeName, sizeUUID).First(&existing).Error; err == nil {
		return nil, errors.New("size already exists for this category")
	}

	size.SizeName = req.SizeName
	size.DisplayName = req.DisplayName
	size.SortOrder = req.SortOrder
	size.IsActive = req.IsActive

	if err := s.db.Save(&size).Error; err != nil {
		return nil, fmt.Errorf("failed to update category size: %w", err)
	}

	response := s.toCategorySizeResponse(&size)
	return &response, nil
}

// DeleteCategorySize soft deletes a category size
func (s *CategorySizeService) DeleteCategorySize(id string) error {
	sizeUUID, err := uuid.Parse(id)
	if err != nil {
		return errors.New("invalid size ID")
	}

	var size models.CategorySize
	if err := s.db.Where("id = ? AND deleted_at IS NULL", sizeUUID).First(&size).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("category size not found")
		}
		return fmt.Errorf("failed to fetch category size: %w", err)
	}

	// Check if any active variants use this size
	var variantCount int64
	if err := s.db.Table("brand_variants").
		Where("category_id = ? AND size = ? AND is_active = ?",
			size.CategoryID, size.SizeName, true).
		Count(&variantCount).Error; err != nil {
		return fmt.Errorf("failed to check variants: %w", err)
	}

	if variantCount > 0 {
		return fmt.Errorf("cannot delete size - %d active variant(s) are using it", variantCount)
	}

	// Proceed with soft delete
	if err := s.db.Delete(&size).Error; err != nil {
		return fmt.Errorf("failed to delete category size: %w", err)
	}

	return nil
}

// BulkCreateCategorySizes creates multiple category sizes at once
func (s *CategorySizeService) BulkCreateCategorySizes(categoryID string, sizeNames []string) ([]CategorySizeResponse, error) {
	categoryUUID, err := uuid.Parse(categoryID)
	if err != nil {
		return nil, errors.New("invalid category ID")
	}

	var sizes []models.CategorySize
	for i, sizeName := range sizeNames {
		sizes = append(sizes, models.CategorySize{
			CategoryID:  categoryUUID,
			SizeName:    sizeName,
			DisplayName: sizeName,
			SortOrder:   i,
			IsActive:    true,
		})
	}

	if err := s.db.Create(&sizes).Error; err != nil {
		return nil, fmt.Errorf("failed to create category sizes: %w", err)
	}

	return s.toCategorySizeResponses(sizes), nil
}

// Helper methods

func (s *CategorySizeService) toCategorySizeResponse(size *models.CategorySize) CategorySizeResponse {
	return CategorySizeResponse{
		ID:          size.ID.String(),
		CategoryID:  size.CategoryID.String(),
		SizeName:    size.SizeName,
		DisplayName: size.DisplayName,
		SortOrder:   size.SortOrder,
		IsActive:    size.IsActive,
		CreatedAt:   size.CreatedAt,
		UpdatedAt:   size.UpdatedAt,
	}
}

func (s *CategorySizeService) toCategorySizeResponses(sizes []models.CategorySize) []CategorySizeResponse {
	responses := make([]CategorySizeResponse, len(sizes))
	for i, size := range sizes {
		responses[i] = s.toCategorySizeResponse(&size)
	}
	return responses
}

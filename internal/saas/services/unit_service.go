package services

import (
	"fmt"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/saas/models"
)

type UnitService struct {
	db *gorm.DB
}

func NewUnitService(db *gorm.DB) *UnitService {
	return &UnitService{db: db}
}

func (s *UnitService) GetAllUnits() ([]models.Unit, error) {
	var units []models.Unit
	if err := s.db.Order("sort_order ASC, name ASC").Find(&units).Error; err != nil {
		return nil, fmt.Errorf("failed to get units: %w", err)
	}
	return units, nil
}

func (s *UnitService) GetUnitByID(id uuid.UUID) (*models.Unit, error) {
	var unit models.Unit
	if err := s.db.First(&unit, id).Error; err != nil {
		return nil, fmt.Errorf("unit not found: %w", err)
	}
	return &unit, nil
}

func (s *UnitService) GetUnitsByType(unitType string) ([]models.Unit, error) {
	var units []models.Unit
	if err := s.db.Where("unit_type = ? AND is_active = true", unitType).Order("sort_order ASC").Find(&units).Error; err != nil {
		return nil, fmt.Errorf("failed to get units by type: %w", err)
	}
	return units, nil
}

func (s *UnitService) CreateUnit(req models.CreateUnitRequest) (*models.Unit, error) {
	// Check symbol uniqueness
	var count int64
	s.db.Model(&models.Unit{}).Where("symbol = ?", req.Symbol).Count(&count)
	if count > 0 {
		return nil, fmt.Errorf("unit with symbol '%s' already exists", req.Symbol)
	}

	unit := &models.Unit{
		ID:               uuid.New(),
		Name:             req.Name,
		Symbol:           req.Symbol,
		UnitType:         req.UnitType,
		ConversionFactor: req.ConversionFactor,
		IsActive:         true,
		SortOrder:        req.SortOrder,
	}

	if err := s.db.Create(unit).Error; err != nil {
		return nil, fmt.Errorf("failed to create unit: %w", err)
	}
	return unit, nil
}

func (s *UnitService) UpdateUnit(id uuid.UUID, req models.UpdateUnitRequest) (*models.Unit, error) {
	var unit models.Unit
	if err := s.db.First(&unit, id).Error; err != nil {
		return nil, fmt.Errorf("unit not found: %w", err)
	}

	if req.Name != nil {
		unit.Name = *req.Name
	}
	if req.Symbol != nil {
		// Check uniqueness
		var count int64
		s.db.Model(&models.Unit{}).Where("symbol = ? AND id != ?", *req.Symbol, id).Count(&count)
		if count > 0 {
			return nil, fmt.Errorf("unit with symbol '%s' already exists", *req.Symbol)
		}
		unit.Symbol = *req.Symbol
	}
	if req.UnitType != nil {
		unit.UnitType = *req.UnitType
	}
	if req.ConversionFactor != nil {
		unit.ConversionFactor = *req.ConversionFactor
	}
	if req.IsActive != nil {
		unit.IsActive = *req.IsActive
	}
	if req.SortOrder != nil {
		unit.SortOrder = *req.SortOrder
	}

	if err := s.db.Save(&unit).Error; err != nil {
		return nil, fmt.Errorf("failed to update unit: %w", err)
	}
	return &unit, nil
}

func (s *UnitService) DeleteUnit(id uuid.UUID) error {
	result := s.db.Delete(&models.Unit{}, id)
	if result.Error != nil {
		return fmt.Errorf("failed to delete unit: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("unit not found")
	}
	return nil
}

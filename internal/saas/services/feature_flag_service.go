package services

import (
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/saas/models"
)

type FeatureFlagService struct {
	db *gorm.DB
}

func NewFeatureFlagService(db *gorm.DB) *FeatureFlagService {
	return &FeatureFlagService{db: db}
}

func (s *FeatureFlagService) GetAllFlags() ([]models.FeatureFlag, error) {
	var flags []models.FeatureFlag
	if err := s.db.Order("name ASC").Find(&flags).Error; err != nil {
		return nil, fmt.Errorf("failed to get feature flags: %w", err)
	}
	return flags, nil
}

func (s *FeatureFlagService) GetFlagByKey(key string) (*models.FeatureFlag, error) {
	var flag models.FeatureFlag
	if err := s.db.Where("key = ?", key).First(&flag).Error; err != nil {
		return nil, fmt.Errorf("feature flag not found: %w", err)
	}
	return &flag, nil
}

func (s *FeatureFlagService) CreateFlag(req models.CreateFeatureFlagRequest) (*models.FeatureFlag, error) {
	var count int64
	s.db.Model(&models.FeatureFlag{}).Where("key = ?", req.Key).Count(&count)
	if count > 0 {
		return nil, fmt.Errorf("feature flag with key '%s' already exists", req.Key)
	}

	flag := &models.FeatureFlag{
		ID:                uuid.New(),
		Name:              req.Name,
		Key:               req.Key,
		Description:       req.Description,
		Enabled:           req.Enabled,
		RolloutPercentage: req.RolloutPercentage,
		TargetTenants:     req.TargetTenants,
		Metadata:          req.Metadata,
	}

	if err := s.db.Create(flag).Error; err != nil {
		return nil, fmt.Errorf("failed to create feature flag: %w", err)
	}
	return flag, nil
}

func (s *FeatureFlagService) UpdateFlag(key string, req models.UpdateFeatureFlagRequest) (*models.FeatureFlag, error) {
	var flag models.FeatureFlag
	if err := s.db.Where("key = ?", key).First(&flag).Error; err != nil {
		return nil, fmt.Errorf("feature flag not found: %w", err)
	}

	if req.Name != nil {
		flag.Name = *req.Name
	}
	if req.Description != nil {
		flag.Description = *req.Description
	}
	if req.Enabled != nil {
		flag.Enabled = *req.Enabled
	}
	if req.RolloutPercentage != nil {
		flag.RolloutPercentage = *req.RolloutPercentage
	}
	if req.TargetTenants != nil {
		flag.TargetTenants = *req.TargetTenants
	}
	if req.Metadata != nil {
		flag.Metadata = *req.Metadata
	}

	if err := s.db.Save(&flag).Error; err != nil {
		return nil, fmt.Errorf("failed to update feature flag: %w", err)
	}
	return &flag, nil
}

func (s *FeatureFlagService) DeleteFlag(key string) error {
	result := s.db.Where("key = ?", key).Delete(&models.FeatureFlag{})
	if result.Error != nil {
		return fmt.Errorf("failed to delete feature flag: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("feature flag not found")
	}
	return nil
}

func (s *FeatureFlagService) IsFeatureEnabled(key string, tenantID uuid.UUID) (bool, error) {
	var flag models.FeatureFlag
	if err := s.db.Where("key = ?", key).First(&flag).Error; err != nil {
		return false, nil // Feature not found = disabled
	}

	if !flag.Enabled {
		return false, nil
	}

	// Check target tenants if specified
	if flag.TargetTenants != "" && flag.TargetTenants != "[]" {
		var targetTenants []string
		if err := json.Unmarshal([]byte(flag.TargetTenants), &targetTenants); err == nil {
			tenantStr := tenantID.String()
			for _, t := range targetTenants {
				if t == tenantStr {
					return true, nil
				}
			}
			return false, nil // Tenant not in target list
		}
	}

	return true, nil
}

// System Configuration methods

func (s *FeatureFlagService) GetAllConfigs(category string) ([]models.SystemConfiguration, error) {
	var configs []models.SystemConfiguration
	query := s.db.Model(&models.SystemConfiguration{})
	if category != "" {
		query = query.Where("category = ?", category)
	}
	if err := query.Order("category ASC, key ASC").Find(&configs).Error; err != nil {
		return nil, fmt.Errorf("failed to get configs: %w", err)
	}
	// Mask secret values
	for i := range configs {
		if configs[i].IsSecret {
			configs[i].Value = "***"
		}
	}
	return configs, nil
}

func (s *FeatureFlagService) UpdateConfig(key string, req models.UpdateConfigRequest) (*models.SystemConfiguration, error) {
	var config models.SystemConfiguration
	if err := s.db.Where("key = ?", key).First(&config).Error; err != nil {
		return nil, fmt.Errorf("config not found: %w", err)
	}

	config.Value = req.Value
	if req.Description != "" {
		config.Description = req.Description
	}

	if err := s.db.Save(&config).Error; err != nil {
		return nil, fmt.Errorf("failed to update config: %w", err)
	}
	return &config, nil
}

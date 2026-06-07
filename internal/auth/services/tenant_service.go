package services

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"gorm.io/gorm"
)

// TenantService handles tenant and shop management operations
type TenantService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewTenantService creates a new tenant service
func NewTenantService(db *database.DB, cache *cache.Cache) *TenantService {
	return &TenantService{
		db:    db,
		cache: cache,
	}
}

// CreateShopRequest represents shop creation request
type CreateShopRequest struct {
	Name          string  `json:"name" binding:"required"`
	Address       string  `json:"address" binding:"required"`
	Phone         string  `json:"phone"`
	LicenseNumber string  `json:"license_number"`
	LicenseFile   string  `json:"license_file"`
	Latitude      float64 `json:"latitude"`
	Longitude     float64 `json:"longitude"`
}

// UpdateShopRequest represents shop update request
type UpdateShopRequest struct {
	Name          *string  `json:"name"`
	Address       *string  `json:"address"`
	Phone         *string  `json:"phone"`
	LicenseNumber *string  `json:"license_number"`
	LicenseFile   *string  `json:"license_file"`
	Latitude      *float64 `json:"latitude"`
	Longitude     *float64 `json:"longitude"`
	IsActive      *bool    `json:"is_active"`
}

// ShopResponse represents shop data in responses
type ShopResponse struct {
	ID            uuid.UUID `json:"id"`
	Name          string    `json:"name"`
	Address       string    `json:"address"`
	Phone         string    `json:"phone"`
	LicenseNumber string    `json:"license_number"`
	LicenseFile   string    `json:"license_file"`
	Latitude      float64   `json:"latitude"`
	Longitude     float64   `json:"longitude"`
	IsActive      bool      `json:"is_active"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// CreateSalesmanRequest represents salesman creation request
type CreateSalesmanRequest struct {
	UserID           uuid.UUID `json:"user_id" binding:"required"`
	ShopID           uuid.UUID `json:"shop_id" binding:"required"`
	EmployeeID       string    `json:"employee_id"`
	Name             string    `json:"name" binding:"required"`
	Phone            string    `json:"phone" binding:"required"`
	Address          string    `json:"address"`
	CertificateImage string    `json:"certificate_image"`
}

// UpdateSalesmanRequest represents salesman update request
type UpdateSalesmanRequest struct {
	ShopID           *uuid.UUID `json:"shop_id"`
	EmployeeID       *string    `json:"employee_id"`
	Name             *string    `json:"name"`
	Phone            *string    `json:"phone"`
	Address          *string    `json:"address"`
	CertificateImage *string    `json:"certificate_image"`
	IsActive         *bool      `json:"is_active"`
}

// SalesmanResponse represents salesman data in responses
type SalesmanResponse struct {
	ID               uuid.UUID     `json:"id"`
	UserID           uuid.UUID     `json:"user_id"`
	User             *UserResponse `json:"user,omitempty"`
	ShopID           uuid.UUID     `json:"shop_id"`
	Shop             *ShopResponse `json:"shop,omitempty"`
	EmployeeID       string        `json:"employee_id"`
	Name             string        `json:"name"`
	Phone            string        `json:"phone"`
	Address          string        `json:"address"`
	CertificateImage string        `json:"certificate_image"`
	JoinDate         time.Time     `json:"join_date"`
	IsActive         bool          `json:"is_active"`
	CreatedAt        time.Time     `json:"created_at"`
	UpdatedAt        time.Time     `json:"updated_at"`
}

// GetShops returns all shops for a tenant
func (s *TenantService) GetShops(ctx context.Context, tenantID uuid.UUID) ([]*ShopResponse, error) {
	var shops []models.Shop

	err := s.db.Where("tenant_id = ?", tenantID).
		Order("name").
		Find(&shops).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get shops: %w", err)
	}

	shopResponses := make([]*ShopResponse, len(shops))
	for i, shop := range shops {
		shopResponses[i] = s.mapShopToResponse(&shop)
	}

	return shopResponses, nil
}

// GetShopsForUser returns shops based on user role
// - Admin/Manager/Assistant Manager: All tenant shops
// - Executive: Only shops mapped via the executive_shops join table
// - Salesman: Only their single assigned shop
func (s *TenantService) GetShopsForUser(ctx context.Context, userID, tenantID uuid.UUID, role string) ([]*ShopResponse, error) {
	switch role {
	case models.RoleSalesman:
		return s.getSalesmanShops(ctx, userID, tenantID)
	case models.RoleExecutive:
		return s.getExecutiveShops(ctx, userID, tenantID)
	default:
		return s.GetShops(ctx, tenantID)
	}
}

// getSalesmanShops returns the single shop the salesman is assigned to.
func (s *TenantService) getSalesmanShops(ctx context.Context, userID, tenantID uuid.UUID) ([]*ShopResponse, error) {
	var salesman models.Salesman
	err := s.db.Preload("Shop").
		Where("user_id = ? AND tenant_id = ?", userID, tenantID).
		First(&salesman).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return []*ShopResponse{}, nil
		}
		return nil, fmt.Errorf("failed to get salesman shops: %w", err)
	}

	if salesman.Shop != nil {
		return []*ShopResponse{s.mapShopToResponse(salesman.Shop)}, nil
	}
	return []*ShopResponse{}, nil
}

// getExecutiveShops returns the shops mapped to an executive via executive_shops.
// Inactive or soft-deleted shops are filtered out so the picker never lists them.
func (s *TenantService) getExecutiveShops(ctx context.Context, userID, tenantID uuid.UUID) ([]*ShopResponse, error) {
	var shops []models.Shop
	err := s.db.
		Joins("JOIN executive_shops es ON es.shop_id = shops.id AND es.deleted_at IS NULL").
		Where("es.user_id = ? AND es.tenant_id = ? AND shops.tenant_id = ? AND shops.is_active = ?",
			userID, tenantID, tenantID, true).
		Order("shops.name").
		Find(&shops).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get executive shops: %w", err)
	}

	out := make([]*ShopResponse, len(shops))
	for i := range shops {
		out[i] = s.mapShopToResponse(&shops[i])
	}
	return out, nil
}

// GetExecutiveShopIDs returns just the assigned shop UUIDs for an executive
// (used when serialising UserResponse).
func (s *TenantService) GetExecutiveShopIDs(ctx context.Context, userID, tenantID uuid.UUID) ([]uuid.UUID, error) {
	var ids []uuid.UUID
	err := s.db.Model(&models.ExecutiveShop{}).
		Where("user_id = ? AND tenant_id = ?", userID, tenantID).
		Pluck("shop_id", &ids).Error
	if err != nil {
		return nil, fmt.Errorf("failed to list executive shop ids: %w", err)
	}
	return ids, nil
}

// ReplaceExecutiveShops sets the executive's shop assignments to exactly the
// given set, atomically. All shop IDs must belong to the tenant. An empty
// shopIDs slice clears all assignments.
func (s *TenantService) ReplaceExecutiveShops(ctx context.Context, userID, tenantID uuid.UUID, shopIDs []uuid.UUID) error {
	// Validate every shop belongs to this tenant before touching anything.
	if len(shopIDs) > 0 {
		var count int64
		if err := s.db.Model(&models.Shop{}).
			Where("id IN ? AND tenant_id = ?", shopIDs, tenantID).
			Count(&count).Error; err != nil {
			return fmt.Errorf("failed to validate shops: %w", err)
		}
		if int(count) != len(shopIDs) {
			return errors.New("one or more shops do not belong to this tenant")
		}
	}

	return s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Unscoped().
			Where("user_id = ? AND tenant_id = ?", userID, tenantID).
			Delete(&models.ExecutiveShop{}).Error; err != nil {
			return fmt.Errorf("failed to clear executive shops: %w", err)
		}
		if len(shopIDs) == 0 {
			return nil
		}
		rows := make([]models.ExecutiveShop, len(shopIDs))
		tid := tenantID
		for i, sid := range shopIDs {
			rows[i] = models.ExecutiveShop{
				TenantModel: models.TenantModel{TenantID: &tid},
				UserID:      userID,
				ShopID:      sid,
			}
		}
		if err := tx.Create(&rows).Error; err != nil {
			return fmt.Errorf("failed to insert executive shops: %w", err)
		}
		return nil
	})
}

// GetShopByID returns shop by ID
func (s *TenantService) GetShopByID(ctx context.Context, shopID, tenantID uuid.UUID) (*ShopResponse, error) {
	var shop models.Shop

	err := s.db.Where("id = ? AND tenant_id = ?", shopID, tenantID).First(&shop).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("shop not found")
		}
		return nil, fmt.Errorf("failed to get shop: %w", err)
	}

	return s.mapShopToResponse(&shop), nil
}

// CreateShop creates a new shop
func (s *TenantService) CreateShop(ctx context.Context, req CreateShopRequest, tenantID uuid.UUID) (*ShopResponse, error) {
	// Check if shop name already exists for this tenant
	var existingShop models.Shop
	if err := s.db.Where("name = ? AND tenant_id = ?", req.Name, tenantID).First(&existingShop).Error; err == nil {
		return nil, errors.New("shop with this name already exists")
	}

	// Check if license number already exists for this tenant (skip if empty)
	if req.LicenseNumber != "" {
		if err := s.db.Where("license_number = ? AND tenant_id = ?", req.LicenseNumber, tenantID).First(&existingShop).Error; err == nil {
			return nil, errors.New("shop with this license number already exists")
		}
	}

	shop := models.Shop{
		TenantModel:   models.TenantModel{TenantID: &tenantID},
		Name:          req.Name,
		Address:       req.Address,
		Phone:         req.Phone,
		LicenseNumber: req.LicenseNumber,
		LicenseFile:   req.LicenseFile,
		Latitude:      req.Latitude,
		Longitude:     req.Longitude,
		IsActive:      true,
	}

	if err := s.db.Create(&shop).Error; err != nil {
		return nil, fmt.Errorf("failed to create shop: %w", err)
	}

	return s.mapShopToResponse(&shop), nil
}

// UpdateShop updates shop information
func (s *TenantService) UpdateShop(ctx context.Context, shopID, tenantID uuid.UUID, req UpdateShopRequest) (*ShopResponse, error) {
	var shop models.Shop

	err := s.db.Where("id = ? AND tenant_id = ?", shopID, tenantID).First(&shop).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("shop not found")
		}
		return nil, fmt.Errorf("failed to find shop: %w", err)
	}

	// Update fields if provided
	updates := make(map[string]interface{})

	if req.Name != nil {
		// Check if name already exists for another shop
		var existingShop models.Shop
		if err := s.db.Where("name = ? AND tenant_id = ? AND id != ?", *req.Name, tenantID, shopID).First(&existingShop).Error; err == nil {
			return nil, errors.New("shop with this name already exists")
		}
		updates["name"] = *req.Name
		shop.Name = *req.Name
	}
	if req.Address != nil {
		updates["address"] = *req.Address
		shop.Address = *req.Address
	}
	if req.Phone != nil {
		updates["phone"] = *req.Phone
		shop.Phone = *req.Phone
	}
	if req.LicenseNumber != nil {
		// Check if license number already exists for another shop (skip if empty)
		if *req.LicenseNumber != "" {
			var existingShop models.Shop
			if err := s.db.Where("license_number = ? AND tenant_id = ? AND id != ?", *req.LicenseNumber, tenantID, shopID).First(&existingShop).Error; err == nil {
				return nil, errors.New("shop with this license number already exists")
			}
		}
		updates["license_number"] = *req.LicenseNumber
		shop.LicenseNumber = *req.LicenseNumber
	}
	if req.LicenseFile != nil {
		updates["license_file"] = *req.LicenseFile
		shop.LicenseFile = *req.LicenseFile
	}
	if req.Latitude != nil {
		updates["latitude"] = *req.Latitude
		shop.Latitude = *req.Latitude
	}
	if req.Longitude != nil {
		updates["longitude"] = *req.Longitude
		shop.Longitude = *req.Longitude
	}
	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
		shop.IsActive = *req.IsActive
	}

	if len(updates) > 0 {
		if err := s.db.Model(&shop).Updates(updates).Error; err != nil {
			return nil, fmt.Errorf("failed to update shop: %w", err)
		}
	}

	return s.mapShopToResponse(&shop), nil
}

// GetSalesmen returns all salesmen for a tenant
func (s *TenantService) GetSalesmen(ctx context.Context, tenantID uuid.UUID) ([]*SalesmanResponse, error) {
	var salesmen []models.Salesman

	err := s.db.Where("tenant_id = ?", tenantID).
		Preload("User").
		Preload("Shop").
		Order("name").
		Find(&salesmen).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get salesmen: %w", err)
	}

	salesmanResponses := make([]*SalesmanResponse, len(salesmen))
	for i, salesman := range salesmen {
		salesmanResponses[i] = s.mapSalesmanToResponse(&salesman)
	}

	return salesmanResponses, nil
}

// GetSalesmanByID returns salesman by ID
func (s *TenantService) GetSalesmanByID(ctx context.Context, salesmanID, tenantID uuid.UUID) (*SalesmanResponse, error) {
	var salesman models.Salesman

	err := s.db.Where("id = ? AND tenant_id = ?", salesmanID, tenantID).
		Preload("User").
		Preload("Shop").
		First(&salesman).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("salesman not found")
		}
		return nil, fmt.Errorf("failed to get salesman: %w", err)
	}

	return s.mapSalesmanToResponse(&salesman), nil
}

// CreateSalesman creates a new salesman
func (s *TenantService) CreateSalesman(ctx context.Context, req CreateSalesmanRequest, tenantID uuid.UUID) (*SalesmanResponse, error) {
	// Verify user exists and belongs to this tenant
	var user models.User
	if err := s.db.Where("id = ? AND tenant_id = ?", req.UserID, tenantID).First(&user).Error; err != nil {
		return nil, errors.New("user not found or doesn't belong to this tenant")
	}

	// Verify shop exists and belongs to this tenant
	var shop models.Shop
	if err := s.db.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		return nil, errors.New("shop not found or doesn't belong to this tenant")
	}

	// Generate employee ID if not provided
	employeeID := req.EmployeeID
	if employeeID == "" {
		employeeID = utils.GenerateEmployeeID()
	}

	// Check if employee ID already exists
	var existingSalesman models.Salesman
	if err := s.db.Where("employee_id = ? AND tenant_id = ?", employeeID, tenantID).First(&existingSalesman).Error; err == nil {
		return nil, errors.New("employee ID already exists")
	}

	salesman := models.Salesman{
		TenantModel:      models.TenantModel{TenantID: &tenantID},
		UserID:           req.UserID,
		ShopID:           req.ShopID,
		EmployeeID:       employeeID,
		Name:             req.Name,
		Phone:            req.Phone,
		Address:          req.Address,
		CertificateImage: req.CertificateImage,
		JoinDate:         time.Now(),
		IsActive:         true,
	}

	if err := s.db.Create(&salesman).Error; err != nil {
		return nil, fmt.Errorf("failed to create salesman: %w", err)
	}

	// Load relations for response
	s.db.Preload("User").Preload("Shop").First(&salesman, salesman.ID)

	return s.mapSalesmanToResponse(&salesman), nil
}

// UpdateSalesman updates salesman information
func (s *TenantService) UpdateSalesman(ctx context.Context, salesmanID, tenantID uuid.UUID, req UpdateSalesmanRequest) (*SalesmanResponse, error) {
	var salesman models.Salesman

	err := s.db.Where("id = ? AND tenant_id = ?", salesmanID, tenantID).
		Preload("User").
		Preload("Shop").
		First(&salesman).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("salesman not found")
		}
		return nil, fmt.Errorf("failed to find salesman: %w", err)
	}

	// Update fields if provided
	updates := make(map[string]interface{})

	if req.ShopID != nil {
		// Verify shop exists and belongs to this tenant
		var shop models.Shop
		if err := s.db.Where("id = ? AND tenant_id = ?", *req.ShopID, tenantID).First(&shop).Error; err != nil {
			return nil, errors.New("shop not found or doesn't belong to this tenant")
		}
		updates["shop_id"] = *req.ShopID
		salesman.ShopID = *req.ShopID
	}
	if req.EmployeeID != nil {
		// Check if employee ID already exists for another salesman
		var existingSalesman models.Salesman
		if err := s.db.Where("employee_id = ? AND tenant_id = ? AND id != ?", *req.EmployeeID, tenantID, salesmanID).First(&existingSalesman).Error; err == nil {
			return nil, errors.New("employee ID already exists")
		}
		updates["employee_id"] = *req.EmployeeID
		salesman.EmployeeID = *req.EmployeeID
	}
	if req.Name != nil {
		updates["name"] = *req.Name
		salesman.Name = *req.Name
	}
	if req.Phone != nil {
		updates["phone"] = *req.Phone
		salesman.Phone = *req.Phone
	}
	if req.Address != nil {
		updates["address"] = *req.Address
		salesman.Address = *req.Address
	}
	if req.CertificateImage != nil {
		updates["certificate_image"] = *req.CertificateImage
		salesman.CertificateImage = *req.CertificateImage
	}
	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
		salesman.IsActive = *req.IsActive
	}

	if len(updates) > 0 {
		if err := s.db.Model(&salesman).Updates(updates).Error; err != nil {
			return nil, fmt.Errorf("failed to update salesman: %w", err)
		}
	}

	// Reload relations
	s.db.Preload("User").Preload("Shop").First(&salesman, salesman.ID)

	return s.mapSalesmanToResponse(&salesman), nil
}

// Helper methods

func (s *TenantService) mapShopToResponse(shop *models.Shop) *ShopResponse {
	return &ShopResponse{
		ID:            shop.ID,
		Name:          shop.Name,
		Address:       shop.Address,
		Phone:         shop.Phone,
		LicenseNumber: shop.LicenseNumber,
		LicenseFile:   shop.LicenseFile,
		Latitude:      shop.Latitude,
		Longitude:     shop.Longitude,
		IsActive:      shop.IsActive,
		CreatedAt:     shop.CreatedAt,
		UpdatedAt:     shop.UpdatedAt,
	}
}

func (s *TenantService) mapSalesmanToResponse(salesman *models.Salesman) *SalesmanResponse {
	response := &SalesmanResponse{
		ID:               salesman.ID,
		UserID:           salesman.UserID,
		ShopID:           salesman.ShopID,
		EmployeeID:       salesman.EmployeeID,
		Name:             salesman.Name,
		Phone:            salesman.Phone,
		Address:          salesman.Address,
		CertificateImage: salesman.CertificateImage,
		JoinDate:         salesman.JoinDate,
		IsActive:         salesman.IsActive,
		CreatedAt:        salesman.CreatedAt,
		UpdatedAt:        salesman.UpdatedAt,
	}

	if salesman.User != nil {
		response.User = &UserResponse{
			ID:           salesman.User.ID,
			Username:     salesman.User.Username,
			Email:        salesman.User.Email,
			FirstName:    salesman.User.FirstName,
			LastName:     salesman.User.LastName,
			Role:         salesman.User.Role,
			IsActive:     salesman.User.IsActive,
			ProfileImage: salesman.User.ProfileImage,
		}
	}

	if salesman.Shop != nil {
		response.Shop = s.mapShopToResponse(salesman.Shop)
	}

	return response
}

// SaaS Admin Methods

// GetAllTenants returns all tenants in the system (SaaS Admin only)
func (s *TenantService) GetAllTenants(ctx context.Context) ([]*models.Tenant, error) {
	var tenants []models.Tenant

	err := s.db.Order("created_at DESC").Find(&tenants).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get all tenants: %w", err)
	}

	// Convert to pointer slice
	result := make([]*models.Tenant, len(tenants))
	for i := range tenants {
		result[i] = &tenants[i]
	}

	return result, nil
}

// GetSystemStats returns system-wide statistics (SaaS Admin only)
func (s *TenantService) GetSystemStats(ctx context.Context) (map[string]interface{}, error) {
	stats := make(map[string]interface{})

	// Count tenants
	var tenantCount int64
	if err := s.db.Model(&models.Tenant{}).Count(&tenantCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count tenants: %w", err)
	}
	stats["total_tenants"] = tenantCount

	// Count total users
	var userCount int64
	if err := s.db.Model(&models.User{}).Count(&userCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count users: %w", err)
	}
	stats["total_users"] = userCount

	// Count total shops
	var shopCount int64
	if err := s.db.Model(&models.Shop{}).Count(&shopCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count shops: %w", err)
	}
	stats["total_shops"] = shopCount

	// Count active vs inactive tenants
	var activeTenants, inactiveTenants int64
	if err := s.db.Model(&models.Tenant{}).Where("is_active = ?", true).Count(&activeTenants).Error; err != nil {
		return nil, fmt.Errorf("failed to count active tenants: %w", err)
	}
	if err := s.db.Model(&models.Tenant{}).Where("is_active = ?", false).Count(&inactiveTenants).Error; err != nil {
		return nil, fmt.Errorf("failed to count inactive tenants: %w", err)
	}
	stats["active_tenants"] = activeTenants
	stats["inactive_tenants"] = inactiveTenants

	return stats, nil
}

// GetAllShops returns all shops across all tenants (SaaS Admin only)
func (s *TenantService) GetAllShops(ctx context.Context) ([]*models.Shop, error) {
	var shops []models.Shop

	err := s.db.Preload("Tenant").Order("created_at DESC").Find(&shops).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get all shops: %w", err)
	}

	// Convert to pointer slice
	result := make([]*models.Shop, len(shops))
	for i := range shops {
		result[i] = &shops[i]
	}
	return result, nil
}

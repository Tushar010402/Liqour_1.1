package utils

import (
	"context"
	"fmt"
	"log"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// ShopAccessLevel defines the level of shop access for different roles
type ShopAccessLevel int

const (
	// ShopAccessNone - no shop access (invalid state)
	ShopAccessNone ShopAccessLevel = iota
	// ShopAccessAssigned - access only to assigned shop (salesmen)
	ShopAccessAssigned
	// ShopAccessAll - access to all shops in tenant (managers, admins, etc.)
	ShopAccessAll
)

// RolesWithRestrictedShopAccess lists roles that can only see their assigned shop
// All other roles see all shops in their tenant
var RolesWithRestrictedShopAccess = map[string]bool{
	"salesman": true,
	// Add other restricted roles here if needed in the future
	// "delivery_agent": true,
}

// RolesWithFullShopAccess lists roles that can see all shops in their tenant
var RolesWithFullShopAccess = map[string]bool{
	"admin":             true,
	"manager":           true,
	"assistant_manager": true,
	"executive":         true,
	"owner":             true,
	"saas_admin":        true, // SaaS admin sees all shops across all tenants
}

// GetShopAccessLevel returns the shop access level for a given role
func GetShopAccessLevel(role string) ShopAccessLevel {
	if RolesWithRestrictedShopAccess[role] {
		return ShopAccessAssigned
	}
	if RolesWithFullShopAccess[role] {
		return ShopAccessAll
	}
	// Unknown roles default to no access for security
	log.Printf("[SECURITY] Unknown role '%s' requested shop access - denying", role)
	return ShopAccessNone
}

// IsShopRestricted returns true if the role can only access assigned shops
func IsShopRestricted(role string) bool {
	return GetShopAccessLevel(role) == ShopAccessAssigned
}

// HasFullShopAccess returns true if the role can access all shops
func HasFullShopAccess(role string) bool {
	return GetShopAccessLevel(role) == ShopAccessAll
}

// ShopAccessResult contains the result of a shop access check
type ShopAccessResult struct {
	AccessLevel   ShopAccessLevel
	AllowedShopID *uuid.UUID // nil means all shops allowed (or none if AccessLevel is None)
	Reason        string
}

// GetUserShopAccess determines what shops a user can access
// This is the central function for shop access control
func GetUserShopAccess(ctx context.Context, db *gorm.DB, userID, tenantID uuid.UUID, userRole string) (*ShopAccessResult, error) {
	accessLevel := GetShopAccessLevel(userRole)

	switch accessLevel {
	case ShopAccessAll:
		log.Printf("[ShopAccess] User %s (role: %s) granted full shop access for tenant %s",
			userID, userRole, tenantID)
		return &ShopAccessResult{
			AccessLevel:   ShopAccessAll,
			AllowedShopID: nil,
			Reason:        fmt.Sprintf("Role '%s' has full shop access", userRole),
		}, nil

	case ShopAccessAssigned:
		// Look up assigned shop from salesmen table
		shopID, err := lookupSalesmanShop(ctx, db, userID, tenantID)
		if err != nil {
			log.Printf("[ShopAccess] Error looking up shop for salesman %s: %v", userID, err)
			return nil, fmt.Errorf("failed to lookup shop assignment: %w", err)
		}
		if shopID == nil {
			log.Printf("[ShopAccess] WARNING: Salesman %s has no shop assigned in tenant %s",
				userID, tenantID)
			return &ShopAccessResult{
				AccessLevel:   ShopAccessAssigned,
				AllowedShopID: nil,
				Reason:        "Salesman has no shop assigned",
			}, nil
		}
		log.Printf("[ShopAccess] Salesman %s restricted to shop %s", userID, *shopID)
		return &ShopAccessResult{
			AccessLevel:   ShopAccessAssigned,
			AllowedShopID: shopID,
			Reason:        fmt.Sprintf("Salesman assigned to shop %s", *shopID),
		}, nil

	case ShopAccessNone:
		log.Printf("[ShopAccess] DENIED: Unknown role '%s' for user %s", userRole, userID)
		return &ShopAccessResult{
			AccessLevel:   ShopAccessNone,
			AllowedShopID: nil,
			Reason:        fmt.Sprintf("Unknown role '%s' - access denied", userRole),
		}, nil

	default:
		return nil, fmt.Errorf("unexpected access level: %d", accessLevel)
	}
}

// lookupSalesmanShop retrieves the shop_id for a salesman from the salesmen table
func lookupSalesmanShop(ctx context.Context, db *gorm.DB, userID, tenantID uuid.UUID) (*uuid.UUID, error) {
	var result struct {
		ShopID uuid.UUID
	}

	err := db.WithContext(ctx).
		Table("salesmen").
		Select("shop_id").
		Where("user_id = ? AND tenant_id = ?", userID, tenantID).
		First(&result).Error

	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil // Not a salesman or no assignment
		}
		return nil, err
	}

	return &result.ShopID, nil
}

// ValidateShopAccess checks if a user can access a specific shop
// Returns error if access is denied
func ValidateShopAccess(ctx context.Context, db *gorm.DB, userID, tenantID, requestedShopID uuid.UUID, userRole string) error {
	access, err := GetUserShopAccess(ctx, db, userID, tenantID, userRole)
	if err != nil {
		return err
	}

	switch access.AccessLevel {
	case ShopAccessAll:
		return nil // Full access granted

	case ShopAccessAssigned:
		if access.AllowedShopID == nil {
			return fmt.Errorf("user has no shop assigned")
		}
		if *access.AllowedShopID != requestedShopID {
			log.Printf("[ShopAccess] BLOCKED: User %s (shop %s) tried to access shop %s",
				userID, *access.AllowedShopID, requestedShopID)
			return fmt.Errorf("access denied: you can only access your assigned shop")
		}
		return nil

	case ShopAccessNone:
		return fmt.Errorf("access denied: %s", access.Reason)

	default:
		return fmt.Errorf("unexpected access level")
	}
}

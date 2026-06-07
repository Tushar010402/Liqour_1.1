package models

// Permission constants for SaaS admin operations
const (
	PermManageTeam          = "manage_team"
	PermManageTenants       = "manage_tenants"
	PermManageBrands        = "manage_brands"
	PermManageSubscriptions = "manage_subscriptions"
	PermManagePlans         = "manage_plans"
	PermManageDiscounts     = "manage_discounts"
	PermViewAnalytics       = "view_analytics"
	PermSystemAdmin         = "system_admin"
	PermManageMasterData    = "manage_master_data"
	PermViewAuditLogs       = "view_audit_logs"
)

// AllPermissions lists all available permissions
var AllPermissions = []string{
	PermManageTeam,
	PermManageTenants,
	PermManageBrands,
	PermManageSubscriptions,
	PermManagePlans,
	PermManageDiscounts,
	PermViewAnalytics,
	PermSystemAdmin,
	PermManageMasterData,
	PermViewAuditLogs,
}

// RoleDefaultPermissions maps roles to their default permissions
var RoleDefaultPermissions = map[string][]string{
	"super_admin": AllPermissions,
	"saas_admin": {
		PermManageTenants,
		PermManageBrands,
		PermManageSubscriptions,
		PermManagePlans,
		PermManageDiscounts,
		PermViewAnalytics,
		PermSystemAdmin,
		PermManageMasterData,
		PermViewAuditLogs,
	},
	"admin": {
		PermManageBrands,
		PermManageTenants,
		PermViewAnalytics,
		PermManageMasterData,
	},
}

// GetDefaultPermissions returns the default permissions for a role
func GetDefaultPermissions(role string) []string {
	if perms, ok := RoleDefaultPermissions[role]; ok {
		return perms
	}
	return []string{}
}

// HasPermission checks if a user has a specific permission
func HasPermission(userPermissions []string, required string) bool {
	for _, p := range userPermissions {
		if p == required {
			return true
		}
	}
	return false
}

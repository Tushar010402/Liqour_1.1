package utils

// RoleLevel maps role names to numeric hierarchy levels
// Higher number = higher authority
var RoleLevel = map[string]int{
	"salesman":          1,
	"executive":         2,
	"assistant_manager": 3,
	"manager":           4,
	"admin":             5,
	"owner":             6,
}

// GetAllowedRoles returns roles that the given role can see (self + below)
// Users can only see users at their level or below in the hierarchy
func GetAllowedRoles(userRole string) []string {
	userLevel, ok := RoleLevel[userRole]
	if !ok {
		return []string{} // Unknown role sees nothing
	}

	allowed := []string{}
	for role, level := range RoleLevel {
		if level <= userLevel {
			allowed = append(allowed, role)
		}
	}
	return allowed
}

// GetRoleLevel returns the hierarchy level for a role
// Returns -1 if role is unknown
func GetRoleLevel(role string) int {
	level, ok := RoleLevel[role]
	if !ok {
		return -1
	}
	return level
}

// CanSeeRole returns true if viewerRole can see targetRole's data
func CanSeeRole(viewerRole, targetRole string) bool {
	viewerLevel := GetRoleLevel(viewerRole)
	targetLevel := GetRoleLevel(targetRole)

	if viewerLevel == -1 || targetLevel == -1 {
		return false
	}

	return viewerLevel >= targetLevel
}

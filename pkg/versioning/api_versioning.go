package versioning

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// APIVersion represents an API version
type APIVersion struct {
	Major      int    `json:"major"`
	Minor      int    `json:"minor"`
	Patch      int    `json:"patch"`
	PreRelease string `json:"pre_release,omitempty"`
	String     string `json:"version"`
}

// ParseVersion parses a version string (e.g., "v1.2.3", "1.2.3-beta")
func ParseVersion(version string) (*APIVersion, error) {
	// Remove 'v' prefix if present
	version = strings.TrimPrefix(version, "v")
	
	// Split pre-release if present
	parts := strings.Split(version, "-")
	versionPart := parts[0]
	var preRelease string
	if len(parts) > 1 {
		preRelease = parts[1]
	}
	
	// Split major.minor.patch
	versionNumbers := strings.Split(versionPart, ".")
	if len(versionNumbers) < 1 {
		return nil, fmt.Errorf("invalid version format: %s", version)
	}
	
	major, err := strconv.Atoi(versionNumbers[0])
	if err != nil {
		return nil, fmt.Errorf("invalid major version: %s", versionNumbers[0])
	}
	
	minor := 0
	if len(versionNumbers) > 1 {
		minor, err = strconv.Atoi(versionNumbers[1])
		if err != nil {
			return nil, fmt.Errorf("invalid minor version: %s", versionNumbers[1])
		}
	}
	
	patch := 0
	if len(versionNumbers) > 2 {
		patch, err = strconv.Atoi(versionNumbers[2])
		if err != nil {
			return nil, fmt.Errorf("invalid patch version: %s", versionNumbers[2])
		}
	}
	
	return &APIVersion{
		Major:      major,
		Minor:      minor,
		Patch:      patch,
		PreRelease: preRelease,
		String:     fmt.Sprintf("v%d.%d.%d", major, minor, patch),
	}, nil
}

// IsCompatible checks if the requested version is compatible with the current version
func (v *APIVersion) IsCompatible(requested *APIVersion) bool {
	// Major version must match
	if v.Major != requested.Major {
		return false
	}
	
	// Current minor version must be >= requested minor version
	if v.Minor < requested.Minor {
		return false
	}
	
	// If minor versions match, current patch must be >= requested patch
	if v.Minor == requested.Minor && v.Patch < requested.Patch {
		return false
	}
	
	return true
}

// Compare compares two versions (-1: less, 0: equal, 1: greater)
func (v *APIVersion) Compare(other *APIVersion) int {
	if v.Major != other.Major {
		if v.Major > other.Major {
			return 1
		}
		return -1
	}
	
	if v.Minor != other.Minor {
		if v.Minor > other.Minor {
			return 1
		}
		return -1
	}
	
	if v.Patch != other.Patch {
		if v.Patch > other.Patch {
			return 1
		}
		return -1
	}
	
	return 0
}

// VersionManager manages API versioning
type VersionManager struct {
	currentVersion    *APIVersion
	supportedVersions []*APIVersion
	deprecatedVersions map[string]string // version -> deprecation message
	logger           *zap.Logger
}

// NewVersionManager creates a new version manager
func NewVersionManager(currentVersion string, supportedVersions []string, logger *zap.Logger) (*VersionManager, error) {
	current, err := ParseVersion(currentVersion)
	if err != nil {
		return nil, fmt.Errorf("invalid current version: %w", err)
	}
	
	supported := make([]*APIVersion, len(supportedVersions))
	for i, v := range supportedVersions {
		parsed, err := ParseVersion(v)
		if err != nil {
			return nil, fmt.Errorf("invalid supported version %s: %w", v, err)
		}
		supported[i] = parsed
	}
	
	return &VersionManager{
		currentVersion:     current,
		supportedVersions:  supported,
		deprecatedVersions: make(map[string]string),
		logger:            logger,
	}, nil
}

// VersioningMiddleware creates middleware for API versioning
func (vm *VersionManager) VersioningMiddleware() gin.HandlerFunc {
	return gin.HandlerFunc(func(c *gin.Context) {
		// Try to get version from different sources
		version := vm.extractVersion(c)
		
		if version == "" {
			// Default to current version if none specified
			version = vm.currentVersion.String
		}
		
		// Parse and validate version
		requestedVersion, err := ParseVersion(version)
		if err != nil {
			vm.logger.Warn("Invalid API version requested",
				zap.String("version", version),
				zap.Error(err),
			)
			c.JSON(400, gin.H{
				"error":   "Invalid API version",
				"message": fmt.Sprintf("Invalid version format: %s", version),
				"details": err.Error(),
			})
			c.Abort()
			return
		}
		
		// Check if version is supported
		if !vm.isVersionSupported(requestedVersion) {
			c.JSON(400, gin.H{
				"error":             "Unsupported API version",
				"message":           fmt.Sprintf("API version %s is not supported", version),
				"current_version":   vm.currentVersion.String,
				"supported_versions": vm.getSupportedVersionStrings(),
			})
			c.Abort()
			return
		}
		
		// Check for deprecated versions
		if deprecationMsg, isDeprecated := vm.deprecatedVersions[requestedVersion.String]; isDeprecated {
			c.Header("X-API-Deprecation-Warning", deprecationMsg)
			c.Header("X-API-Current-Version", vm.currentVersion.String)
			
			vm.logger.Warn("Deprecated API version used",
				zap.String("version", requestedVersion.String),
				zap.String("client_ip", c.ClientIP()),
				zap.String("user_agent", c.Request.UserAgent()),
			)
		}
		
		// Set version in context for handlers to use
		c.Set("api_version", requestedVersion)
		c.Set("api_version_string", requestedVersion.String)
		
		// Add version headers to response
		c.Header("X-API-Version", requestedVersion.String)
		c.Header("X-API-Current-Version", vm.currentVersion.String)
		
		c.Next()
	})
}

// extractVersion extracts API version from request
func (vm *VersionManager) extractVersion(c *gin.Context) string {
	// 1. Check Accept header (e.g., application/vnd.liquorpro.v1+json)
	if accept := c.GetHeader("Accept"); accept != "" {
		if version := vm.extractVersionFromAcceptHeader(accept); version != "" {
			return version
		}
	}
	
	// 2. Check custom header
	if version := c.GetHeader("X-API-Version"); version != "" {
		return version
	}
	
	// 3. Check query parameter
	if version := c.Query("version"); version != "" {
		return version
	}
	
	// 4. Check URL path (e.g., /v1/api/...)
	if version := vm.extractVersionFromPath(c.Request.URL.Path); version != "" {
		return version
	}
	
	return ""
}

// extractVersionFromAcceptHeader extracts version from Accept header
func (vm *VersionManager) extractVersionFromAcceptHeader(accept string) string {
	// Look for pattern like "application/vnd.liquorpro.v1+json"
	if strings.Contains(accept, "application/vnd.liquorpro.") {
		parts := strings.Split(accept, ".")
		for _, part := range parts {
			if strings.HasPrefix(part, "v") && len(part) > 1 {
				// Extract version part before any '+'
				versionPart := strings.Split(part, "+")[0]
				return versionPart
			}
		}
	}
	return ""
}

// extractVersionFromPath extracts version from URL path
func (vm *VersionManager) extractVersionFromPath(path string) string {
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) > 0 && strings.HasPrefix(parts[0], "v") {
		return parts[0]
	}
	return ""
}

// isVersionSupported checks if a version is supported
func (vm *VersionManager) isVersionSupported(requested *APIVersion) bool {
	for _, supported := range vm.supportedVersions {
		if supported.Major == requested.Major && 
		   supported.Minor == requested.Minor &&
		   supported.Patch == requested.Patch {
			return true
		}
	}
	return false
}

// getSupportedVersionStrings returns supported versions as strings
func (vm *VersionManager) getSupportedVersionStrings() []string {
	versions := make([]string, len(vm.supportedVersions))
	for i, v := range vm.supportedVersions {
		versions[i] = v.String
	}
	return versions
}

// DeprecateVersion marks a version as deprecated
func (vm *VersionManager) DeprecateVersion(version, message string) error {
	_, err := ParseVersion(version)
	if err != nil {
		return fmt.Errorf("invalid version to deprecate: %w", err)
	}
	
	vm.deprecatedVersions[version] = message
	vm.logger.Info("API version deprecated",
		zap.String("version", version),
		zap.String("message", message),
	)
	
	return nil
}

// GetVersionInfo returns version information endpoint
func (vm *VersionManager) GetVersionInfo(c *gin.Context) {
	info := gin.H{
		"current_version":    vm.currentVersion,
		"supported_versions": vm.supportedVersions,
		"deprecated_versions": vm.deprecatedVersions,
		"api_info": gin.H{
			"name":        "LiquorPro API",
			"description": "Multi-tenant liquor management system API",
			"contact": gin.H{
				"name":  "LiquorPro Support",
				"email": "support@liquorpro.com",
			},
		},
	}
	
	c.JSON(200, info)
}

// VersionAwareHandler wraps handlers with version-specific logic
type VersionAwareHandler struct {
	handlers map[string]gin.HandlerFunc
	fallback gin.HandlerFunc
	logger   *zap.Logger
}

// NewVersionAwareHandler creates a new version-aware handler
func NewVersionAwareHandler(fallback gin.HandlerFunc, logger *zap.Logger) *VersionAwareHandler {
	return &VersionAwareHandler{
		handlers: make(map[string]gin.HandlerFunc),
		fallback: fallback,
		logger:   logger,
	}
}

// AddVersionHandler adds a handler for a specific version
func (vah *VersionAwareHandler) AddVersionHandler(version string, handler gin.HandlerFunc) {
	vah.handlers[version] = handler
}

// Handle handles the request with version-specific logic
func (vah *VersionAwareHandler) Handle(c *gin.Context) {
	version := c.GetString("api_version_string")
	
	// Try to find version-specific handler
	if handler, exists := vah.handlers[version]; exists {
		vah.logger.Debug("Using version-specific handler",
			zap.String("version", version),
			zap.String("path", c.Request.URL.Path),
		)
		handler(c)
		return
	}
	
	// Fall back to default handler
	if vah.fallback != nil {
		vah.logger.Debug("Using fallback handler",
			zap.String("version", version),
			zap.String("path", c.Request.URL.Path),
		)
		vah.fallback(c)
		return
	}
	
	c.JSON(501, gin.H{
		"error":   "Handler not implemented",
		"message": fmt.Sprintf("No handler implemented for version %s", version),
	})
}

// VersionedResponse wraps responses with version information
type VersionedResponse struct {
	Data       interface{} `json:"data"`
	Version    string      `json:"version"`
	Timestamp  int64       `json:"timestamp"`
	Deprecated bool        `json:"deprecated,omitempty"`
}

// WrapResponse wraps a response with version information
func WrapResponse(c *gin.Context, data interface{}) VersionedResponse {
	version := c.GetString("api_version_string")
	deprecated := c.GetHeader("X-API-Deprecation-Warning") != ""
	
	response := VersionedResponse{
		Data:      data,
		Version:   version,
		Timestamp: c.GetTime().Unix(),
	}
	
	if deprecated {
		response.Deprecated = true
	}
	
	return response
}

// ContentNegotiation handles content type negotiation based on version
func (vm *VersionManager) ContentNegotiation() gin.HandlerFunc {
	return gin.HandlerFunc(func(c *gin.Context) {
		version := c.GetString("api_version_string")
		accept := c.GetHeader("Accept")
		
		// Default content type
		contentType := "application/json"
		
		// Version-specific content type logic
		if version != "" {
			parsedVersion, _ := ParseVersion(version)
			
			// Example: v2+ supports additional content types
			if parsedVersion.Major >= 2 {
				if strings.Contains(accept, "application/vnd.api+json") {
					contentType = "application/vnd.api+json"
				}
			}
		}
		
		c.Header("Content-Type", contentType)
		c.Next()
	})
}

// RateLimitByVersion applies different rate limits based on API version
func (vm *VersionManager) RateLimitByVersion() gin.HandlerFunc {
	return gin.HandlerFunc(func(c *gin.Context) {
		version := c.GetString("api_version_string")
		
		if version != "" {
			parsedVersion, _ := ParseVersion(version)
			
			// Example: Lower rate limits for older versions
			var limit int
			switch parsedVersion.Major {
			case 1:
				limit = 100 // requests per minute
			case 2:
				limit = 200
			default:
				limit = 300
			}
			
			c.Header("X-RateLimit-Version", fmt.Sprintf("v%d", parsedVersion.Major))
			c.Header("X-RateLimit-Limit", fmt.Sprintf("%d", limit))
		}
		
		c.Next()
	})
}

// SetupVersioningRoutes sets up versioning-related routes
func (vm *VersionManager) SetupVersioningRoutes(router gin.IRouter) {
	router.GET("/version", vm.GetVersionInfo)
	router.GET("/versions", vm.GetVersionInfo) // Alias
}
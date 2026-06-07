package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// SDUIHandler handles Server-Driven UI endpoints
type SDUIHandler struct {
	db     *gorm.DB
	cache  *cache.Cache
	logger *zap.Logger
}

// NewSDUIHandler creates a new SDUI handler
func NewSDUIHandler(db *gorm.DB, cache *cache.Cache, logger *zap.Logger) *SDUIHandler {
	return &SDUIHandler{db: db, cache: cache, logger: logger}
}

// ============================================================================
// MODELS
// ============================================================================

// AppBanner represents a dynamic banner/announcement
type AppBanner struct {
	ID          string     `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	TenantID    *string    `json:"tenant_id,omitempty" gorm:"type:uuid;index"`
	Title       string     `json:"title" gorm:"not null"`
	Subtitle    string     `json:"subtitle,omitempty"`
	ImageURL    string     `json:"image_url,omitempty"`
	ActionType  string     `json:"action_type,omitempty"`  // navigate, url, none
	ActionValue string     `json:"action_value,omitempty"` // route path or URL
	BgColor     string     `json:"bg_color" gorm:"default:'#0D47A1'"`
	TextColor   string     `json:"text_color" gorm:"default:'#FFFFFF'"`
	Priority    int        `json:"priority" gorm:"default:0"`
	StartsAt    *time.Time `json:"starts_at,omitempty"`
	EndsAt      *time.Time `json:"ends_at,omitempty"`
	IsActive    bool       `json:"is_active" gorm:"default:true"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

func (AppBanner) TableName() string { return "app_banners" }

// TenantTheme represents server-driven theme for a tenant
type TenantTheme struct {
	ID               string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	TenantID         string  `json:"tenant_id" gorm:"type:uuid;uniqueIndex;not null"`
	PrimaryColor     string  `json:"primary_color" gorm:"default:'#0D47A1'"`
	PrimaryLight     string  `json:"primary_light" gorm:"default:'#2196F3'"`
	AccentColor      string  `json:"accent_color" gorm:"default:'#FF6B35'"`
	BackgroundColor  string  `json:"background_color" gorm:"default:'#F5F6FA'"`
	SurfaceColor     string  `json:"surface_color" gorm:"default:'#FFFFFF'"`
	DarkCardColor    string  `json:"dark_card_color" gorm:"default:'#0D1B3E'"`
	ErrorColor       string  `json:"error_color" gorm:"default:'#E53935'"`
	SuccessColor     string  `json:"success_color" gorm:"default:'#10B981'"`
	WarningColor     string  `json:"warning_color" gorm:"default:'#F59E0B'"`
	LogoURL          string  `json:"logo_url,omitempty"`
	DarkModeEnabled  bool    `json:"dark_mode_enabled" gorm:"default:false"`
	FontFamily       string  `json:"font_family" gorm:"default:'Nunito'"`
	HeadingFont      string  `json:"heading_font" gorm:"default:'Nunito'"`
	UpdatedAt        time.Time `json:"updated_at"`
}

func (TenantTheme) TableName() string { return "tenant_themes" }

// AppVersion represents app version management
type AppVersion struct {
	ID                 string    `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Platform           string    `json:"platform" gorm:"not null"` // android, ios
	LatestVersion      string    `json:"latest_version" gorm:"not null"`
	MinRequiredVersion string    `json:"min_required_version" gorm:"not null"`
	ForceUpdate        bool      `json:"force_update" gorm:"default:false"`
	UpdateURL          string    `json:"update_url,omitempty"`
	Changelog          string    `json:"changelog,omitempty"`
	ReleasedAt         time.Time `json:"released_at"`
}

func (AppVersion) TableName() string { return "app_versions" }

// SDUIScreenConfig stores screen definitions
type SDUIScreenConfig struct {
	ID        string          `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	ScreenID  string          `json:"screen_id" gorm:"uniqueIndex:idx_screen_role_tenant;not null"` // e.g., "home", "sales_list"
	Role      string          `json:"role" gorm:"uniqueIndex:idx_screen_role_tenant;not null;default:'*'"` // salesman, manager, admin, * (all)
	TenantID  *string         `json:"tenant_id,omitempty" gorm:"uniqueIndex:idx_screen_role_tenant;type:uuid"`
	Title     string          `json:"title"`
	Config    json.RawMessage `json:"config" gorm:"type:jsonb;not null"` // Full screen widget tree
	IsActive  bool            `json:"is_active" gorm:"default:true"`
	Version   int             `json:"version" gorm:"default:1"`
	CreatedAt time.Time       `json:"created_at"`
	UpdatedAt time.Time       `json:"updated_at"`
}

func (SDUIScreenConfig) TableName() string { return "sdui_screen_configs" }

// ============================================================================
// RESPONSE TYPES
// ============================================================================

// SDUIWidget represents a single widget in the SDUI tree
type SDUIWidget struct {
	Type       string                 `json:"type"`                  // widget type: card, text, button, list, grid, etc.
	ID         string                 `json:"id,omitempty"`          // unique identifier for the widget
	Props      map[string]interface{} `json:"props,omitempty"`       // widget-specific properties
	Style      map[string]interface{} `json:"style,omitempty"`       // CSS-like styling
	Data       map[string]interface{} `json:"data,omitempty"`        // static data bindings
	API        *SDUIAPIBinding        `json:"api,omitempty"`         // dynamic data from API
	Action     *SDUIAction            `json:"action,omitempty"`      // tap/click action
	Children   []SDUIWidget           `json:"children,omitempty"`    // nested widgets
	Conditions *SDUICondition         `json:"conditions,omitempty"`  // conditional rendering
}

// SDUIAPIBinding defines how a widget fetches data
type SDUIAPIBinding struct {
	Endpoint       string `json:"endpoint"`                   // API endpoint
	Method         string `json:"method,omitempty"`           // GET, POST (default GET)
	Field          string `json:"field,omitempty"`             // extract specific field from response
	RefreshSeconds int    `json:"refresh_seconds,omitempty"`  // auto-refresh interval
	CacheMinutes   int    `json:"cache_minutes,omitempty"`    // cache duration
}

// SDUIAction defines what happens on user interaction
type SDUIAction struct {
	Type  string                 `json:"type"`            // navigate, api_call, bottom_sheet, modal, refresh, back
	Route string                 `json:"route,omitempty"` // navigation route
	API   string                 `json:"api,omitempty"`   // API endpoint to call
	Sheet string                 `json:"sheet,omitempty"` // bottom sheet ID
	Args  map[string]interface{} `json:"args,omitempty"`  // additional arguments
}

// SDUICondition defines when a widget should be visible
type SDUICondition struct {
	Roles     []string `json:"roles,omitempty"`      // visible for these roles
	NotRoles  []string `json:"not_roles,omitempty"`  // hidden for these roles
	Feature   string   `json:"feature,omitempty"`    // requires feature flag
	MinVersion string  `json:"min_version,omitempty"` // requires app version
}

// HelpConfig defines the 1-click help button behavior
type HelpConfig struct {
	Enabled        bool   `json:"enabled"`
	ButtonPosition string `json:"button_position"` // bottom_right, bottom_left
	ButtonIcon     string `json:"button_icon"`     // help, support_agent, headset_mic
	ButtonColor    string `json:"button_color"`
	HelpAPI        string `json:"help_api"`        // endpoint to call when user taps help
	ChatEnabled    bool   `json:"chat_enabled"`    // in-app chat support
	PhoneNumber    string `json:"phone_number,omitempty"` // direct call support
	WhatsAppNumber string `json:"whatsapp_number,omitempty"`
}

// TrackingConfig defines user analytics and session tracking
type TrackingConfig struct {
	Enabled            bool     `json:"enabled"`
	TrackScreenViews   bool     `json:"track_screen_views"`
	TrackUserActions   bool     `json:"track_user_actions"`   // button taps, form submits
	TrackAPILatency    bool     `json:"track_api_latency"`    // slow API detection
	TrackErrors        bool     `json:"track_errors"`         // crash/error tracking
	TrackLocation      bool     `json:"track_location"`       // GPS on key actions
	SessionTimeout     int      `json:"session_timeout_mins"` // inactivity timeout
	BatchSize          int      `json:"batch_size"`           // events per batch
	FlushIntervalSecs  int      `json:"flush_interval_secs"`  // send batch every N seconds
	SensitiveFields    []string `json:"sensitive_fields"`     // fields to mask in tracking
	EventsAPI          string   `json:"events_api"`           // endpoint to send events
}

// AppConfigResponse is the main SDUI config response
type AppConfigResponse struct {
	ConfigVersion string                 `json:"config_version"`
	GeneratedAt   time.Time              `json:"generated_at"`
	App           AppInfo                `json:"app"`
	Theme         ThemeConfig            `json:"theme"`
	Announcement  *AnnouncementConfig    `json:"announcement,omitempty"`
	Banners       []BannerConfig         `json:"banners,omitempty"`
	Navigation    NavigationConfig       `json:"navigation"`
	Screens       map[string]SDUIWidget  `json:"screens"`
	FeatureFlags  map[string]bool        `json:"feature_flags"`
	Sheets        map[string]SDUIWidget  `json:"sheets,omitempty"`
	Help          HelpConfig             `json:"help"`
	Tracking      TrackingConfig         `json:"tracking"`
}

type AppInfo struct {
	LatestVersion      string `json:"latest_version"`
	MinRequiredVersion string `json:"min_required_version"`
	ForceUpdate        bool   `json:"force_update"`
	UpdateURL          string `json:"update_url,omitempty"`
	MaintenanceMode    bool   `json:"maintenance_mode"`
	MaintenanceMessage string `json:"maintenance_message,omitempty"`
}

type ThemeConfig struct {
	PrimaryColor    string `json:"primary_color"`
	PrimaryLight    string `json:"primary_light"`
	AccentColor     string `json:"accent_color"`
	BackgroundColor string `json:"background_color"`
	SurfaceColor    string `json:"surface_color"`
	DarkCardColor   string `json:"dark_card_color"`
	ErrorColor      string `json:"error_color"`
	SuccessColor    string `json:"success_color"`
	WarningColor    string `json:"warning_color"`
	FontFamily      string `json:"font_family"`
	HeadingFont     string `json:"heading_font"`
	DarkMode        bool   `json:"dark_mode"`
	LogoURL         string `json:"logo_url,omitempty"`
}

type AnnouncementConfig struct {
	ID          string  `json:"id"`
	Type        string  `json:"type"` // banner, fullscreen, bottom_sheet
	Title       string  `json:"title"`
	Body        string  `json:"body,omitempty"`
	ImageURL    string  `json:"image_url,omitempty"`
	BgColor     string  `json:"bg_color"`
	TextColor   string  `json:"text_color"`
	Action      *SDUIAction `json:"action,omitempty"`
	Dismissible bool    `json:"dismissible"`
	ShowUntil   string  `json:"show_until,omitempty"`
}

type BannerConfig struct {
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	Subtitle    string     `json:"subtitle,omitempty"`
	ImageURL    string     `json:"image_url,omitempty"`
	BgColor     string     `json:"bg_color"`
	TextColor   string     `json:"text_color"`
	Action      *SDUIAction `json:"action,omitempty"`
}

type NavigationConfig struct {
	BottomNav []NavItem `json:"bottom_nav"`
}

type NavItem struct {
	ID         string    `json:"id"`
	Label      string    `json:"label"`
	Icon       string    `json:"icon"`
	ActiveIcon string    `json:"active_icon,omitempty"`
	Route      string    `json:"route,omitempty"`
	Screen     string    `json:"screen,omitempty"`      // screen_id to render
	BadgeAPI   string    `json:"badge_api,omitempty"`   // API for badge count
	BadgeField string    `json:"badge_field,omitempty"` // field to extract count
	Children   []NavItem `json:"children,omitempty"`    // for "more" tab
	Conditions *SDUICondition `json:"conditions,omitempty"`
}

// ============================================================================
// HANDLERS
// ============================================================================

// GetAppConfig returns the full SDUI configuration
func (h *SDUIHandler) GetAppConfig(c *gin.Context) {
	userRole := c.GetString("role")
	tenantID := c.GetString("tenant_id")
	platform := c.DefaultQuery("platform", "android")

	if userRole == "" {
		userRole = "salesman"
	}

	// Try cache first
	cacheKey := fmt.Sprintf("sdui:config:%s:%s:%s", tenantID, userRole, platform)
	var cached AppConfigResponse
	if err := h.cache.Get(c.Request.Context(), cacheKey, &cached); err == nil {
		c.JSON(http.StatusOK, cached)
		return
	}

	// Build config
	config := h.buildAppConfig(c, tenantID, userRole, platform)

	// Cache for 5 minutes
	h.cache.Set(c.Request.Context(), cacheKey, config, 5*time.Minute)

	c.JSON(http.StatusOK, config)
}

// GetScreen returns a specific screen definition
func (h *SDUIHandler) GetScreen(c *gin.Context) {
	screenID := c.Param("screen_id")
	userRole := c.GetString("role")
	tenantID := c.GetString("tenant_id")

	if screenID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "screen_id is required"})
		return
	}

	screen := h.getScreenForRole(screenID, userRole, tenantID)
	if screen == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "screen not found"})
		return
	}

	c.JSON(http.StatusOK, screen)
}

// GetBanners returns active banners
func (h *SDUIHandler) GetBanners(c *gin.Context) {
	tenantID := c.GetString("tenant_id")
	now := time.Now()

	var banners []AppBanner
	query := h.db.Where("is_active = ?", true).
		Where("(starts_at IS NULL OR starts_at <= ?)", now).
		Where("(ends_at IS NULL OR ends_at >= ?)", now).
		Where("(tenant_id IS NULL OR tenant_id = ?)", tenantID).
		Order("priority DESC, created_at DESC").
		Limit(10)

	if err := query.Find(&banners).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch banners"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"banners": banners})
}

// VersionCheck checks if app needs update
func (h *SDUIHandler) VersionCheck(c *gin.Context) {
	platform := c.DefaultQuery("platform", "android")
	currentVersion := c.DefaultQuery("version", "1.0.0")

	var appVersion AppVersion
	err := h.db.Where("platform = ?", platform).
		Order("released_at DESC").
		First(&appVersion).Error

	if err != nil {
		// No version config — no update needed
		c.JSON(http.StatusOK, gin.H{
			"update_available": false,
			"force_update":     false,
		})
		return
	}

	needsUpdate := currentVersion < appVersion.MinRequiredVersion

	c.JSON(http.StatusOK, gin.H{
		"latest_version":      appVersion.LatestVersion,
		"min_required_version": appVersion.MinRequiredVersion,
		"force_update":        appVersion.ForceUpdate && needsUpdate,
		"update_available":    currentVersion < appVersion.LatestVersion,
		"update_url":          appVersion.UpdateURL,
		"changelog":           appVersion.Changelog,
	})
}

// ============================================================================
// CONFIG BUILDER
// ============================================================================

func (h *SDUIHandler) buildAppConfig(c *gin.Context, tenantID, userRole, platform string) AppConfigResponse {
	config := AppConfigResponse{
		ConfigVersion: fmt.Sprintf("%d", time.Now().Unix()),
		GeneratedAt:   time.Now(),
		App:           h.getAppInfo(platform),
		Theme:         h.getTheme(tenantID),
		Navigation:    h.getNavigation(userRole),
		Screens:       h.getScreens(userRole, tenantID),
		FeatureFlags:  h.getFeatureFlags(tenantID),
		Sheets:        h.getSheets(userRole),
	}

	// Active banners
	config.Banners = h.getActiveBanners(tenantID)

	// Active announcement (highest priority)
	config.Announcement = h.getActiveAnnouncement(tenantID)

	// Help button config
	config.Help = HelpConfig{
		Enabled:        true,
		ButtonPosition: "bottom_right",
		ButtonIcon:     "headset_mic",
		ButtonColor:    "#0D47A1",
		HelpAPI:        "/api/sdui/help/request",
		ChatEnabled:    false,
		PhoneNumber:    "+918630668488",
	}

	// User tracking config
	config.Tracking = TrackingConfig{
		Enabled:           true,
		TrackScreenViews:  true,
		TrackUserActions:  true,
		TrackAPILatency:   true,
		TrackErrors:       true,
		TrackLocation:     false,
		SessionTimeout:    30,
		BatchSize:         20,
		FlushIntervalSecs: 60,
		SensitiveFields:   []string{"password", "otp", "token", "phone"},
		EventsAPI:         "/api/analytics/events",
	}

	return config
}

func (h *SDUIHandler) getAppInfo(platform string) AppInfo {
	var v AppVersion
	h.db.Where("platform = ?", platform).Order("released_at DESC").First(&v)

	return AppInfo{
		LatestVersion:      v.LatestVersion,
		MinRequiredVersion: v.MinRequiredVersion,
		ForceUpdate:        v.ForceUpdate,
		UpdateURL:          v.UpdateURL,
	}
}

func (h *SDUIHandler) getTheme(tenantID string) ThemeConfig {
	// Default theme (salesman design DNA)
	theme := ThemeConfig{
		PrimaryColor:    "#0D47A1",
		PrimaryLight:    "#2196F3",
		AccentColor:     "#FF6B35",
		BackgroundColor: "#F5F6FA",
		SurfaceColor:    "#FFFFFF",
		DarkCardColor:   "#0D1B3E",
		ErrorColor:      "#E53935",
		SuccessColor:    "#10B981",
		WarningColor:    "#F59E0B",
		FontFamily:      "Nunito",
		HeadingFont:     "Nunito",
	}

	// Override with tenant-specific theme if exists
	if tenantID != "" {
		var tt TenantTheme
		if err := h.db.Where("tenant_id = ?", tenantID).First(&tt).Error; err == nil {
			theme.PrimaryColor = tt.PrimaryColor
			theme.PrimaryLight = tt.PrimaryLight
			theme.AccentColor = tt.AccentColor
			theme.BackgroundColor = tt.BackgroundColor
			theme.SurfaceColor = tt.SurfaceColor
			theme.DarkCardColor = tt.DarkCardColor
			theme.ErrorColor = tt.ErrorColor
			theme.SuccessColor = tt.SuccessColor
			theme.WarningColor = tt.WarningColor
			theme.FontFamily = tt.FontFamily
			theme.HeadingFont = tt.HeadingFont
			theme.DarkMode = tt.DarkModeEnabled
			theme.LogoURL = tt.LogoURL
		}
	}

	return theme
}

func (h *SDUIHandler) getNavigation(role string) NavigationConfig {
	switch role {
	case "salesman", "executive":
		return NavigationConfig{
			BottomNav: []NavItem{
				{ID: "home", Label: "Home", Icon: "home", ActiveIcon: "home_filled", Screen: "home"},
				{ID: "inventory", Label: "Inventory", Icon: "inventory_2", ActiveIcon: "inventory_2", Screen: "inventory"},
				{ID: "profile", Label: "Profile", Icon: "person", ActiveIcon: "person", Screen: "profile"},
			},
		}
	case "assistant_manager":
		return NavigationConfig{
			BottomNav: []NavItem{
				{ID: "home", Label: "Home", Icon: "home", ActiveIcon: "home_filled", Screen: "home"},
				{ID: "inventory", Label: "Inventory", Icon: "inventory_2", ActiveIcon: "inventory_2", Screen: "inventory"},
				{ID: "finance", Label: "Finance", Icon: "account_balance_wallet", ActiveIcon: "account_balance_wallet", Screen: "finance",
					BadgeAPI: "/api/finance/cash/collections/pending", BadgeField: "count"},
				{ID: "profile", Label: "Profile", Icon: "person", ActiveIcon: "person", Screen: "profile"},
			},
		}
	default: // manager, admin, owner
		return NavigationConfig{
			BottomNav: []NavItem{
				{ID: "home", Label: "Home", Icon: "home", ActiveIcon: "home_filled", Screen: "home"},
				{ID: "inventory", Label: "Inventory", Icon: "inventory_2", ActiveIcon: "inventory_2", Screen: "inventory"},
				{ID: "sales", Label: "Sales", Icon: "point_of_sale", ActiveIcon: "point_of_sale", Screen: "sales_list",
					BadgeAPI: "/api/sales/pending", BadgeField: "pending_sales"},
				{ID: "finance", Label: "Finance", Icon: "account_balance_wallet", ActiveIcon: "account_balance_wallet", Screen: "finance",
					BadgeAPI: "/api/finance/cash/collections/pending", BadgeField: "count"},
				{ID: "more", Label: "More", Icon: "more_horiz", Children: []NavItem{
					{ID: "reports", Label: "Reports", Icon: "analytics", Screen: "reports"},
					{ID: "staff", Label: "Staff", Icon: "people", Screen: "staff"},
					{ID: "settings", Label: "Settings", Icon: "settings", Screen: "settings"},
					{ID: "excise", Label: "Excise", Icon: "description", Screen: "excise",
						Conditions: &SDUICondition{Roles: []string{"admin", "manager", "owner"}}},
				}},
			},
		}
	}
}

func (h *SDUIHandler) getScreens(role, tenantID string) map[string]SDUIWidget {
	screens := make(map[string]SDUIWidget)

	// Home screen — same layout, different content per role
	screens["home"] = h.buildHomeScreen(role)

	// Inventory — same for all roles
	screens["inventory"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"background": "{{theme.background}}"},
		Children: []SDUIWidget{
			{Type: "product_grid", API: &SDUIAPIBinding{Endpoint: "/api/inventory/products", CacheMinutes: 5},
				Props: map[string]interface{}{"show_stock": true, "enable_selection": role != "salesman" && role != "executive"}},
		},
	}

	// Sales list — manager/admin only
	screens["sales_list"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Sales", "pull_to_refresh": true},
		Children: []SDUIWidget{
			{Type: "date_filter_strip", Props: map[string]interface{}{
				"options": []string{"today", "yesterday", "7d", "15d", "30d"},
				"default": "today",
			}},
			{Type: "sales_record_list", API: &SDUIAPIBinding{Endpoint: "/api/sales/daily-records", RefreshSeconds: 0},
				Props: map[string]interface{}{
					"field":              "records",
					"item_title":         "shop_name",
					"item_subtitle":      "salesman_name",
					"item_amount":        "total_sales_amount",
					"item_date":          "record_date",
					"item_status":        "status",
					"item_id":            "id",
					"item_items":         "total_items",
					"show_approve":       role == "manager" || role == "admin" || role == "owner",
					"show_payment_split": true,
					"empty_icon":         "receipt",
					"empty_text":         "No sales records found",
					"approve_endpoint":   "/api/sales/daily-records",
				}},
		},
	}

	// Finance / Cash Dashboard
	screens["finance"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Cash Management"},
		Children: []SDUIWidget{
			{Type: "cash_balance_card", API: &SDUIAPIBinding{Endpoint: "/api/finance/cash/balance", RefreshSeconds: 30}},
			{Type: "action_tiles", Children: []SDUIWidget{
				{Type: "action_tile", Props: map[string]interface{}{
					"title": "Cash Requests", "icon": "swap_horiz", "subtitle": "Request & track from team",
				}, Action: &SDUIAction{Type: "navigate", Route: "/finance/requests"}},
				{Type: "action_tile", Props: map[string]interface{}{
					"title": "Bank Submissions", "icon": "account_balance",
				}, Action: &SDUIAction{Type: "navigate", Route: "/finance/submissions"}},
				{Type: "action_tile", Props: map[string]interface{}{
					"title": "Approvals", "icon": "check_circle",
				}, Action: &SDUIAction{Type: "navigate", Route: "/finance/approvals"},
					Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner", "assistant_manager"}}},
				{Type: "action_tile", Props: map[string]interface{}{
					"title": "Cash History", "icon": "history",
				}, Action: &SDUIAction{Type: "navigate", Route: "/finance/history"}},
			}},
		},
	}

	// Profile — all roles (SDUI-driven: profile header + ALL settings merged in)
	screens["profile"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"pull_to_refresh": true},
		Children: []SDUIWidget{
			// Profile card with gradient header, details, tagline, edit button
			{Type: "profile_header", Props: map[string]interface{}{
				"show_engagement": true,
				"show_details":    true,
				"show_edit":       true,
				"show_tagline":    true,
				"show_phone":      true,
				"edit_action":     map[string]interface{}{"type": "navigate", "route": "/profile/edit"},
			}},

			// Appearance section
			{Type: "section_header", Props: map[string]interface{}{"title": "Appearance"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Theme", "subtitle": "Customize app appearance", "icon": "palette"},
				Action: &SDUIAction{Type: "bottom_sheet", Sheet: "theme_picker"}},

			// General section
			{Type: "section_header", Props: map[string]interface{}{"title": "General"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Manage Shops", "subtitle": "Add or manage your shop locations", "icon": "store"},
				Action: &SDUIAction{Type: "navigate", Route: "/shops"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "User Management", "subtitle": "Manage users and their roles", "icon": "people"},
				Action: &SDUIAction{Type: "navigate", Route: "/staff"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Expense Headers", "subtitle": "Manage expense categories for daily sales", "icon": "receipt_long"},
				Action: &SDUIAction{Type: "navigate", Route: "/settings/expense-categories"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner", "assistant_manager"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Brand Onboarding", "subtitle": "Add brands and products to your shop inventory", "icon": "local_bar"},
				Action: &SDUIAction{Type: "navigate", Route: "/brand-onboarding"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "AI Stock Setup", "subtitle": "Set opening stock from register photo using AI", "icon": "auto_awesome"},
				Action: &SDUIAction{Type: "navigate", Route: "/ai-stock-setup"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Godam Management", "subtitle": "Manage godams and track payments", "icon": "business_center"},
				Action: &SDUIAction{Type: "navigate", Route: "/vendors"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner", "assistant_manager"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Bank Accounts", "subtitle": "Manage bank accounts for deposits", "icon": "account_balance"},
				Action: &SDUIAction{Type: "navigate", Route: "/bank-accounts"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Expenses", "subtitle": "Track and manage business expenses", "icon": "receipt"},
				Action: &SDUIAction{Type: "navigate", Route: "/expenses"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Notifications", "subtitle": "Manage notification preferences", "icon": "notifications"},
				Action: &SDUIAction{Type: "navigate", Route: "/notifications/preferences"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Security", "subtitle": "Change password and security settings", "icon": "security"},
				Action: &SDUIAction{Type: "navigate", Route: "/security"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Linked Devices", "subtitle": "Manage logged in devices", "icon": "devices"},
				Action: &SDUIAction{Type: "navigate", Route: "/linked-devices"}},

			// Advanced Features section
			{Type: "section_header", Props: map[string]interface{}{"title": "Advanced Features"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner", "assistant_manager"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Finance Matrix", "subtitle": "Unified financial dashboard", "icon": "dashboard_customize"},
				Action: &SDUIAction{Type: "navigate", Route: "/finance-matrix"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Tips Management", "subtitle": "Manage tips and payouts", "icon": "volunteer_activism"},
				Action: &SDUIAction{Type: "navigate", Route: "/tips"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Purcha Report", "subtitle": "Daily stock report with opening, receipt, sale & closing", "icon": "assessment"},
				Action: &SDUIAction{Type: "navigate", Route: "/purcha-report"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Physical Audit", "subtitle": "Cash counting and inventory verification", "icon": "fact_check"},
				Action: &SDUIAction{Type: "navigate", Route: "/physical-audit"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Theft Detection", "subtitle": "Anomaly alerts and investigations", "icon": "security"},
				Action: &SDUIAction{Type: "navigate", Route: "/theft-detection"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},

			// About section
			{Type: "section_header", Props: map[string]interface{}{"title": "About"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "About LiquorPro", "subtitle": "Version 1.0.0", "icon": "info"},
				Action: &SDUIAction{Type: "navigate", Route: "/about"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Help & Support", "subtitle": "Get help with using the app", "icon": "help"},
				Action: &SDUIAction{Type: "navigate", Route: "/help"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Debug Logs", "subtitle": "View and share app logs for troubleshooting", "icon": "bug_report"},
				Action: &SDUIAction{Type: "navigate", Route: "/debug-logs"}},

			// Logout + Danger zone
			{Type: "logout_button"},
			{Type: "danger_zone", Props: map[string]interface{}{
				"title":        "Danger Zone",
				"message":      "Once you delete your account, there is no going back. Please be certain.",
				"button_label": "Delete Account",
			}},
		},
	}

	// Reports — manager/admin
	screens["reports"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Reports"},
		Children: []SDUIWidget{
			{Type: "report_card_grid", Children: []SDUIWidget{
				{Type: "report_card", Props: map[string]interface{}{"title": "P&L Report", "icon": "trending_up", "color": "#10B981"}, Action: &SDUIAction{Type: "navigate", Route: "/reports/pnl"}},
				{Type: "report_card", Props: map[string]interface{}{"title": "Cash Flow", "icon": "account_balance", "color": "#0D47A1"}, Action: &SDUIAction{Type: "navigate", Route: "/reports/cashflow"}},
				{Type: "report_card", Props: map[string]interface{}{"title": "Sales Analytics", "icon": "analytics", "color": "#F59E0B"}, Action: &SDUIAction{Type: "navigate", Route: "/reports/sales"}},
				{Type: "report_card", Props: map[string]interface{}{"title": "Stock Report", "icon": "inventory", "color": "#7C3AED"}, Action: &SDUIAction{Type: "navigate", Route: "/reports/stock"}},
			}},
		},
	}

	// Sales history — all roles (read-only, no approve)
	screens["sales_history"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Sales History", "pull_to_refresh": true},
		Children: []SDUIWidget{
			{Type: "date_filter_strip", Props: map[string]interface{}{
				"options": []string{"today", "yesterday", "7d", "15d", "30d"},
				"default": "today",
			}},
			{Type: "sales_record_list", API: &SDUIAPIBinding{Endpoint: "/api/sales/daily-records", RefreshSeconds: 0},
				Props: map[string]interface{}{
					"field":              "records",
					"item_title":         "shop_name",
					"item_subtitle":      "salesman_name",
					"item_amount":        "total_sales_amount",
					"item_date":          "record_date",
					"item_status":        "status",
					"item_id":            "id",
					"item_items":         "total_items",
					"show_approve":       false,
					"show_payment_split": true,
					"empty_icon":         "receipt",
					"empty_text":         "No sales records found",
				}},
		},
	}

	// Sales entry — salesman, executive, assistant_manager
	screens["sales_entry"] = SDUIWidget{
		Type: "native_sales_wizard",
		Props: map[string]interface{}{
			"steps": []string{"products", "payment", "review"},
			"api_submit":  "/api/sales/daily-records",
			"api_products": "/api/inventory/products",
			"draft_key":   "sales_draft",
		},
	}

	// Sales pending — manager/admin approval list
	screens["sales_pending"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Pending Approvals", "pull_to_refresh": true},
		Children: []SDUIWidget{
			{Type: "sales_record_list", API: &SDUIAPIBinding{Endpoint: "/api/sales/pending", RefreshSeconds: 15},
				Props: map[string]interface{}{
					"field":              "records",
					"item_title":         "shop_name",
					"item_subtitle":      "salesman_name",
					"item_amount":        "total_sales_amount",
					"item_date":          "record_date",
					"item_status":        "status",
					"item_id":            "id",
					"item_items":         "total_items",
					"show_approve":       true,
					"show_payment_split": true,
					"empty_icon":         "receipt",
					"empty_text":         "No pending approvals",
					"approve_endpoint":   "/api/sales/daily-records",
				}},
		},
	}

	// Purchase history
	screens["purchase_history"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Purchase History", "pull_to_refresh": true},
		Children: []SDUIWidget{
			{Type: "date_filter_strip", Props: map[string]interface{}{
				"options": []string{"today", "7d", "30d"},
			}},
			{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/inventory/purchases", RefreshSeconds: 120},
				Props: map[string]interface{}{
					"item_title":    "vendor_name",
					"item_subtitle": "shop_name",
					"item_amount":   "total_amount",
					"item_status":   "status",
					"item_date":     "purchase_date",
					"empty_icon":    "shopping_cart",
					"empty_text":    "No purchases yet",
				}},
		},
	}

	// Cash history
	screens["cash_history"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Cash History", "pull_to_refresh": true},
		Children: []SDUIWidget{
			{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/finance/cash/history"},
				Props: map[string]interface{}{
					"item_title":    "type",
					"item_subtitle": "description",
					"item_amount":   "amount",
					"item_date":     "created_at",
					"empty_icon":    "history",
					"empty_text":    "No transactions yet",
				}},
		},
	}

	// Cash requests
	screens["cash_requests"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Cash Requests", "pull_to_refresh": true},
		Children: []SDUIWidget{
			{Type: "tabbed_view", Props: map[string]interface{}{
				"tabs": []map[string]interface{}{
					{"id": "received", "label": "Received"},
					{"id": "sent", "label": "Sent"},
				},
			}, Children: []SDUIWidget{
				{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/finance/cash/requests?type=received"},
					Props: map[string]interface{}{
						"item_title": "requester_name", "item_amount": "amount", "item_status": "status",
						"show_approve": role == "manager" || role == "admin" || role == "owner" || role == "assistant_manager",
					}},
				{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/finance/cash/requests?type=sent"},
					Props: map[string]interface{}{
						"item_title": "approver_name", "item_amount": "amount", "item_status": "status",
					}},
			}},
		},
	}

	// Cash submit
	screens["cash_submit"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Submit Cash to Bank"},
		Children: []SDUIWidget{
			{Type: "denomination_form", Props: map[string]interface{}{
				"denominations": []int{2000, 500, 200, 100, 50, 20, 10, 5, 2, 1},
				"submit_api":    "/api/finance/cash/submit",
			}},
		},
	}

	// Vendors
	screens["vendors"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Vendors", "pull_to_refresh": true},
		Children: []SDUIWidget{
			{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/finance/vendors", CacheMinutes: 5},
				Props: map[string]interface{}{
					"item_title":    "name",
					"item_subtitle": "phone",
					"item_amount":   "outstanding_balance",
					"item_icon":     "store",
					"empty_icon":    "store",
					"empty_text":    "No vendors yet",
				},
				Action: &SDUIAction{Type: "navigate", Route: "/vendors/{id}"},
			},
		},
	}

	// Expenses
	screens["expenses"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Expenses", "pull_to_refresh": true},
		Children: []SDUIWidget{
			{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/finance/expenses"},
				Props: map[string]interface{}{
					"item_title":    "category_name",
					"item_subtitle": "description",
					"item_amount":   "amount",
					"item_date":     "expense_date",
					"empty_icon":    "receipt",
					"empty_text":    "No expenses recorded",
				}},
			{Type: "fab", Props: map[string]interface{}{
				"icon": "add", "label": "Add Expense",
			}, Action: &SDUIAction{Type: "bottom_sheet", Sheet: "add_expense"}},
		},
	}

	// Reports detail — P&L
	screens["report_pnl"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Profit & Loss"},
		Children: []SDUIWidget{
			{Type: "date_filter_strip", Props: map[string]interface{}{
				"options": []string{"7d", "30d", "this_month", "last_month"},
			}},
			{Type: "chart_widget", API: &SDUIAPIBinding{Endpoint: "/api/finance/reports/profit-loss"},
				Props: map[string]interface{}{
					"chart_type": "bar",
					"x_field":    "period",
					"y_fields":   []string{"revenue", "expenses", "profit"},
					"colors":     []string{"#10B981", "#E53935", "#0D47A1"},
				}},
			{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/finance/reports/profit-loss"},
				Props: map[string]interface{}{
					"item_title": "category", "item_amount": "amount",
				}},
		},
	}

	// Reports detail — Cash Flow
	screens["report_cashflow"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Cash Flow"},
		Children: []SDUIWidget{
			{Type: "date_filter_strip", Props: map[string]interface{}{
				"options": []string{"7d", "30d", "this_month"},
			}},
			{Type: "chart_widget", API: &SDUIAPIBinding{Endpoint: "/api/finance/reports/cash-flow"},
				Props: map[string]interface{}{
					"chart_type": "line",
					"x_field":    "date",
					"y_fields":   []string{"inflow", "outflow"},
					"colors":     []string{"#10B981", "#E53935"},
				}},
		},
	}

	// Reports — Sales Analytics
	screens["report_sales"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Sales Analytics"},
		Children: []SDUIWidget{
			{Type: "date_filter_strip", Props: map[string]interface{}{
				"options": []string{"7d", "30d", "this_month"},
			}},
			{Type: "chart_widget", API: &SDUIAPIBinding{Endpoint: "/api/sales/dashboard/summary"},
				Props: map[string]interface{}{
					"chart_type": "line",
					"x_field":    "date",
					"y_fields":   []string{"total_amount"},
					"colors":     []string{"#0D47A1"},
				}},
			{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/sales/dashboard/summary"},
				Props: map[string]interface{}{
					"field": "top_products",
					"item_title": "product_name", "item_subtitle": "brand_name", "item_amount": "total_amount",
				}},
		},
	}

	// Reports — Stock Report
	screens["report_stock"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Stock Report"},
		Children: []SDUIWidget{
			{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/inventory/stocks"},
				Props: map[string]interface{}{
					"item_title":    "product_name",
					"item_subtitle": "brand_name",
					"item_amount":   "quantity",
					"item_badge":    "low_stock",
					"empty_icon":    "inventory",
					"empty_text":    "No stock data",
				}},
		},
	}

	// Staff — manager/admin
	screens["staff"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Staff", "pull_to_refresh": true},
		Children: []SDUIWidget{
			{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/admin/users", CacheMinutes: 5},
				Props: map[string]interface{}{
					"item_type":     "user_card",
					"item_title":    "first_name",
					"item_subtitle": "role",
					"item_badge":    "is_active",
					"item_icon":     "person",
					"empty_icon":    "people",
					"empty_text":    "No staff members",
				},
				Action: &SDUIAction{Type: "navigate", Route: "/staff/{id}"},
			},
			{Type: "fab", Props: map[string]interface{}{
				"icon": "person_add", "label": "Add Staff",
			}, Action: &SDUIAction{Type: "navigate", Route: "/staff/new"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
		},
	}

	// User form (create/edit staff)
	screens["user_form"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Add Staff Member"},
		Children: []SDUIWidget{
			{Type: "form", Props: map[string]interface{}{
				"submit_api": "/api/admin/users",
				"fields": []map[string]interface{}{
					{"name": "first_name", "label": "First Name", "type": "text", "required": true},
					{"name": "last_name", "label": "Last Name", "type": "text", "required": true},
					{"name": "phone", "label": "Phone Number", "type": "phone", "required": true},
					{"name": "email", "label": "Email", "type": "email"},
					{"name": "role", "label": "Role", "type": "dropdown", "required": true,
						"options": h.getRoleOptionsForUser(role)},
					{"name": "salary", "label": "Salary", "type": "number"},
				},
			}},
		},
	}

	// Settings — all roles (SDUI-driven: profile card, role-based tiles, logout, danger zone)
	screens["settings"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Settings"},
		Children: []SDUIWidget{
			// Profile card at top
			{Type: "profile_card"},

			// Appearance section
			{Type: "section_header", Props: map[string]interface{}{"title": "Appearance"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Theme", "subtitle": "Customize app appearance", "icon": "palette"},
				Action: &SDUIAction{Type: "bottom_sheet", Sheet: "theme_picker"}},

			// General section
			{Type: "section_header", Props: map[string]interface{}{"title": "General"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Manage Shops", "subtitle": "Add or manage your shop locations", "icon": "store"},
				Action: &SDUIAction{Type: "navigate", Route: "/shops"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "User Management", "subtitle": "Manage users and their roles", "icon": "people"},
				Action: &SDUIAction{Type: "navigate", Route: "/staff"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Expense Headers", "subtitle": "Manage expense categories for daily sales", "icon": "receipt_long"},
				Action: &SDUIAction{Type: "navigate", Route: "/settings/expense-categories"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner", "assistant_manager"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Brand Onboarding", "subtitle": "Add brands and products to your shop inventory", "icon": "local_bar"},
				Action: &SDUIAction{Type: "navigate", Route: "/brand-onboarding"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "AI Stock Setup", "subtitle": "Set opening stock from register photo using AI", "icon": "auto_awesome"},
				Action: &SDUIAction{Type: "navigate", Route: "/ai-stock-setup"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Godam Management", "subtitle": "Manage godams and track payments", "icon": "business_center"},
				Action: &SDUIAction{Type: "navigate", Route: "/vendors"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner", "assistant_manager"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Bank Accounts", "subtitle": "Manage bank accounts for deposits", "icon": "account_balance"},
				Action: &SDUIAction{Type: "navigate", Route: "/bank-accounts"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Expenses", "subtitle": "Track and manage business expenses", "icon": "receipt"},
				Action: &SDUIAction{Type: "navigate", Route: "/expenses"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Notifications", "subtitle": "Manage notification preferences", "icon": "notifications"},
				Action: &SDUIAction{Type: "navigate", Route: "/notifications/preferences"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Security", "subtitle": "Change password and security settings", "icon": "security"},
				Action: &SDUIAction{Type: "navigate", Route: "/security"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Linked Devices", "subtitle": "Manage logged in devices", "icon": "devices"},
				Action: &SDUIAction{Type: "navigate", Route: "/linked-devices"}},

			// Advanced Features section
			{Type: "section_header", Props: map[string]interface{}{"title": "Advanced Features"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner", "assistant_manager"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Finance Matrix", "subtitle": "Unified financial dashboard", "icon": "dashboard_customize"},
				Action: &SDUIAction{Type: "navigate", Route: "/finance-matrix"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Tips Management", "subtitle": "Manage tips and payouts", "icon": "volunteer_activism"},
				Action: &SDUIAction{Type: "navigate", Route: "/tips"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Purcha Report", "subtitle": "Daily stock report with opening, receipt, sale & closing", "icon": "assessment"},
				Action: &SDUIAction{Type: "navigate", Route: "/purcha-report"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Physical Audit", "subtitle": "Cash counting and inventory verification", "icon": "fact_check"},
				Action: &SDUIAction{Type: "navigate", Route: "/physical-audit"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Theft Detection", "subtitle": "Anomaly alerts and investigations", "icon": "security"},
				Action: &SDUIAction{Type: "navigate", Route: "/theft-detection"},
				Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}}},

			// About section
			{Type: "section_header", Props: map[string]interface{}{"title": "About"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "About LiquorPro", "subtitle": "Version 1.0.0", "icon": "info"},
				Action: &SDUIAction{Type: "navigate", Route: "/about"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Help & Support", "subtitle": "Get help with using the app", "icon": "help"},
				Action: &SDUIAction{Type: "navigate", Route: "/help"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Debug Logs", "subtitle": "View and share app logs for troubleshooting", "icon": "bug_report"},
				Action: &SDUIAction{Type: "navigate", Route: "/debug-logs"}},

			// Logout + Danger zone
			{Type: "logout_button"},
			{Type: "danger_zone", Props: map[string]interface{}{
				"title":        "Danger Zone",
				"message":      "Once you delete your account, there is no going back. Please be certain.",
				"button_label": "Delete Account",
			}},
		},
	}

	// Profile edit form
	screens["profile_edit"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Edit Profile"},
		Children: []SDUIWidget{
			{Type: "form", Props: map[string]interface{}{
				"submit_api": "/api/auth/profile",
				"method":     "PUT",
				"load_api":   "/api/auth/profile",
				"fields": []map[string]interface{}{
					{"name": "first_name", "label": "First Name", "type": "text", "required": true},
					{"name": "last_name", "label": "Last Name", "type": "text", "required": true},
					{"name": "email", "label": "Email", "type": "email"},
				},
			}},
		},
	}

	// Notifications center
	screens["notifications"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Notifications", "pull_to_refresh": true},
		Children: []SDUIWidget{
			{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/notifications"},
				Props: map[string]interface{}{
					"item_title":    "title",
					"item_subtitle": "body",
					"item_date":     "created_at",
					"item_icon":     "notification_type",
					"empty_icon":    "notifications_none",
					"empty_text":    "No notifications",
				}},
		},
	}

	// Shops management — admin only
	screens["shops"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Shops", "pull_to_refresh": true},
		Children: []SDUIWidget{
			{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/admin/shops", CacheMinutes: 5},
				Props: map[string]interface{}{
					"item_title":    "name",
					"item_subtitle": "address",
					"item_icon":     "store",
					"empty_icon":    "store",
					"empty_text":    "No shops configured",
				},
				Action: &SDUIAction{Type: "navigate", Route: "/shops/{id}"},
			},
			{Type: "fab", Props: map[string]interface{}{
				"icon": "add_business", "label": "Add Shop",
			}, Action: &SDUIAction{Type: "navigate", Route: "/shops/new"}},
		},
	}

	// Shop form
	screens["shop_form"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Add Shop"},
		Children: []SDUIWidget{
			{Type: "form", Props: map[string]interface{}{
				"submit_api": "/api/admin/shops",
				"fields": []map[string]interface{}{
					{"name": "name", "label": "Shop Name", "type": "text", "required": true},
					{"name": "address", "label": "Address", "type": "textarea"},
					{"name": "phone", "label": "Phone", "type": "phone"},
					{"name": "license_number", "label": "License Number", "type": "text"},
				},
			}},
		},
	}

	// Excise — manager/admin
	screens["excise"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Excise & Compliance"},
		Children: []SDUIWidget{
			{Type: "tabbed_view", Props: map[string]interface{}{
				"tabs": []map[string]interface{}{
					{"id": "dashboard", "label": "Dashboard"},
					{"id": "licenses", "label": "Licenses"},
					{"id": "reports", "label": "Daily Reports"},
				},
			}, Children: []SDUIWidget{
				// Dashboard tab
				{Type: "column", Children: []SDUIWidget{
					{Type: "summary_card", API: &SDUIAPIBinding{Endpoint: "/api/excise/summary"},
						Props: map[string]interface{}{"label": "COMPLIANCE STATUS", "icon": "verified", "icon_color": "#10B981"}},
				}},
				// Licenses tab
				{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/excise/licenses"},
					Props: map[string]interface{}{
						"item_title": "license_number", "item_subtitle": "type", "item_date": "expiry_date",
					}},
				// Reports tab
				{Type: "data_list", API: &SDUIAPIBinding{Endpoint: "/api/excise/daily-reports"},
					Props: map[string]interface{}{
						"item_title": "date", "item_subtitle": "status",
					}},
			}},
		},
	}

	// Physical audit — manager/admin
	screens["physical_audit"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Physical Audit"},
		Children: []SDUIWidget{
			{Type: "tabbed_view", Props: map[string]interface{}{
				"tabs": []map[string]interface{}{
					{"id": "overview", "label": "Overview"},
					{"id": "cash", "label": "Cash Audit"},
					{"id": "inventory", "label": "Stock Audit"},
				},
			}, Children: []SDUIWidget{
				{Type: "column", Children: []SDUIWidget{
					{Type: "summary_card", API: &SDUIAPIBinding{Endpoint: "/api/audit/summary"},
						Props: map[string]interface{}{"label": "AUDIT STATUS", "icon": "fact_check", "icon_color": "#7C3AED"}},
				}},
				{Type: "denomination_form", Props: map[string]interface{}{
					"denominations": []int{2000, 500, 200, 100, 50, 20, 10, 5, 2, 1},
					"submit_api":    "/api/audit/cash",
					"title":         "Count Cash",
				}},
				{Type: "product_grid", API: &SDUIAPIBinding{Endpoint: "/api/inventory/stocks"},
					Props: map[string]interface{}{"show_stock": true, "enable_count": true}},
			}},
		},
	}

	// Help & Support
	screens["help"] = SDUIWidget{
		Type: "scaffold",
		Props: map[string]interface{}{"title": "Help & Support"},
		Children: []SDUIWidget{
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Request Help", "icon": "headset_mic"},
				Action: &SDUIAction{Type: "api_call", API: "/api/sdui/help/request"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "Call Support", "icon": "phone"},
				Action: &SDUIAction{Type: "navigate", Route: "tel:+918630668488"}},
			{Type: "settings_tile", Props: map[string]interface{}{"title": "FAQ", "icon": "help"},
				Action: &SDUIAction{Type: "navigate", Route: "/help/faq"}},
		},
	}

	return screens
}

func (h *SDUIHandler) buildHomeScreen(role string) SDUIWidget {
	// Common sections for all roles
	children := []SDUIWidget{
		// Greeting header
		{Type: "greeting_header", Props: map[string]interface{}{
			"show_settings":   true,
			"show_shop_name":  true,
			"show_user_name":  true,
			"show_tagline":    true,
			"show_date_info":  true,
			"settings_action": map[string]interface{}{"type": "navigate", "route": "/settings"},
		}},

		// Date filter strip
		{Type: "date_filter_strip", Props: map[string]interface{}{
			"options":        []string{"today", "yesterday", "7d", "30d"},
			"default":        "yesterday",
			"show_date_cards": true,
		}},
	}

	// Sales summary card — all roles see it
	salesCard := SDUIWidget{
		Type: "summary_card",
		ID:   "sales_summary",
		API:  &SDUIAPIBinding{Endpoint: "/api/sales/dashboard/summary", RefreshSeconds: 60, CacheMinutes: 1},
		Props: map[string]interface{}{
			"icon":          "trending_up",
			"icon_color":    "#0D47A1",
			"label":         "SALES SUMMARY",
			"amount_field":  "todays_sales.total_amount",
			"count_field":   "todays_sales.total_sales",
			"count_label":   "entries",
			"status_field":  "my_status.status",
			"amount_format": "indian",
			"progress_numerator_field":   "unique_products_sold",
			"progress_denominator_field": "total_stocked_products",
			"progress_label":             "sizes sold",
			"button_color":  "#0D47A1",
		},
		Action: &SDUIAction{Type: "navigate", Route: "/sales/history"},
	}

	// Button inside sales card — differs by role
	switch role {
	case "salesman", "executive":
		salesCard.Props["button_label"] = "Enter Daily Sale"
		salesCard.Props["button_icon"] = "point_of_sale"
		salesCard.Props["button_action"] = map[string]interface{}{"type": "navigate", "route": "/sales/entry"}
	case "manager", "admin", "owner":
		salesCard.Props["button_label"] = "View All Sales"
		salesCard.Props["button_icon"] = "list"
		salesCard.Props["button_action"] = map[string]interface{}{"type": "navigate", "route": "/sales/list"}
	case "assistant_manager":
		salesCard.Props["button_label"] = "View Sales"
		salesCard.Props["button_icon"] = "visibility"
		salesCard.Props["button_action"] = map[string]interface{}{"type": "navigate", "route": "/sales/history"}
	}
	children = append(children, salesCard)

	// Purchase card — salesman, executive, manager, admin, owner
	purchaseCard := SDUIWidget{
		Type: "summary_card",
		ID:   "purchase_summary",
		API:  &SDUIAPIBinding{Endpoint: "/api/sales/dashboard/summary", RefreshSeconds: 120},
		Props: map[string]interface{}{
			"icon":          "shopping_cart",
			"icon_color":    "#E53935",
			"label":         "PURCHASE SUMMARY",
			"amount_field":  "purchase_amount",
			"count_field":   "purchase_count",
			"count_label":   "purchases",
			"amount_format": "indian",
			"button_color":  "#E53935",
		},
		Action:     &SDUIAction{Type: "navigate", Route: "/purchases/history"},
		Conditions: &SDUICondition{Roles: []string{"salesman", "executive", "manager", "admin", "owner"}},
	}
	switch role {
	case "salesman", "executive":
		purchaseCard.Props["button_label"] = "Add Purchase"
		purchaseCard.Props["button_icon"] = "add_shopping_cart"
		purchaseCard.Props["button_action"] = map[string]interface{}{"type": "navigate", "route": "/purchases/new"}
	case "manager", "admin", "owner":
		purchaseCard.Props["button_label"] = "View Purchases"
		purchaseCard.Props["button_action"] = map[string]interface{}{"type": "navigate", "route": "/purchases/list"}
	}
	children = append(children, purchaseCard)

	// Day closing card (dark) — salesman, executive, manager, admin, owner, assistant_manager
	dayClosingCard := SDUIWidget{
		Type: "day_closing_card",
		ID:   "day_closing",
		Props: map[string]interface{}{
			"dark_bg":               "#0D1B3E",
			"label":                 "DAY CLOSING RECONCILIATION",
			"expense_label":         "Daily Expenses",
			"cash_label":            "CASH IN HAND",
			"upi_label":             "TOTAL UPI",
			"expense_button_label":  "Add Expenses",
			"expense_button_color":  "#2196F3",
			"use_dashboard_provider": true,
		},
		Conditions: &SDUICondition{Roles: []string{"salesman", "executive", "manager", "admin", "owner", "assistant_manager"}},
	}
	children = append(children, dayClosingCard)

	// Pending approvals — manager/admin only
	pendingSection := SDUIWidget{
		Type: "pending_approvals",
		ID:   "pending_approvals",
		API:  &SDUIAPIBinding{Endpoint: "/api/sales/pending", RefreshSeconds: 30},
		Props: map[string]interface{}{
			"label":      "PENDING APPROVALS",
			"show_count": true,
		},
		Action:     &SDUIAction{Type: "navigate", Route: "/sales/pending"},
		Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}},
	}
	children = append(children, pendingSection)

	// Team tracker — manager/admin
	teamTracker := SDUIWidget{
		Type: "team_submission_tracker",
		ID:   "team_tracker",
		API:  &SDUIAPIBinding{Endpoint: "/api/sales/dashboard/summary", Field: "team_status", RefreshSeconds: 60},
		Props: map[string]interface{}{
			"label": "TEAM SUBMISSION STATUS",
		},
		Conditions: &SDUICondition{Roles: []string{"manager", "admin", "owner"}},
	}
	children = append(children, teamTracker)

	return SDUIWidget{
		Type:  "scaffold",
		Props: map[string]interface{}{"background": "{{theme.background}}", "pull_to_refresh": true, "home_screen": true},
		Children: children,
	}
}

func (h *SDUIHandler) getSheets(role string) map[string]SDUIWidget {
	sheets := map[string]SDUIWidget{
		"cash_details": {
			Type: "bottom_sheet",
			Props: map[string]interface{}{"title": "Cash Details", "snap_points": []float64{0.7}},
			Children: []SDUIWidget{
				{Type: "denomination_form", Props: map[string]interface{}{
					"denominations": []int{2000, 500, 200, 100, 50, 20, 10, 5, 2, 1},
				}},
			},
		},
		"upi_details": {
			Type: "bottom_sheet",
			Props: map[string]interface{}{"title": "UPI Details", "snap_points": []float64{0.5}},
			Children: []SDUIWidget{
				{Type: "upi_form"},
			},
		},
		"add_expense": {
			Type: "bottom_sheet",
			Props: map[string]interface{}{"title": "Add Expense", "snap_points": []float64{0.6}},
			Children: []SDUIWidget{
				{Type: "expense_form", API: &SDUIAPIBinding{Endpoint: "/api/finance/expense-categories"}},
			},
		},
		"theme_picker": {
			Type: "bottom_sheet",
			Props: map[string]interface{}{"title": "Choose Theme", "snap_points": []float64{0.4}},
			Children: []SDUIWidget{
				{Type: "theme_selector", Props: map[string]interface{}{
					"options": []map[string]string{
						{"id": "warm_white", "label": "Warm White", "preview": "#F5F6FA"},
						{"id": "cool_white", "label": "Cool White", "preview": "#F0F7FF"},
						{"id": "dark", "label": "Dark", "preview": "#0F172A"},
					},
				}},
			},
		},
	}

	return sheets
}

func (h *SDUIHandler) getFeatureFlags(tenantID string) map[string]bool {
	// Default flags
	flags := map[string]bool{
		"smart_sale_ai":     true,
		"smart_purchase":    true,
		"smart_stock_setup": true,
		"barcode_scanner":   false,
		"dark_mode":         true,
		"offline_mode":      true,
		"ocr_batch":         true,
		"voice_search":      false,
		"excise_module":     false,
		"physical_audit":    false,
		"theft_detection":   false,
		"tips_module":       false,
		"finance_matrix":    false,
		"push_notifications": true,
	}

	// TODO: Override from database feature_flags table per tenant
	return flags
}

func (h *SDUIHandler) getActiveBanners(tenantID string) []BannerConfig {
	now := time.Now()
	var banners []AppBanner

	h.db.Where("is_active = ?", true).
		Where("(starts_at IS NULL OR starts_at <= ?)", now).
		Where("(ends_at IS NULL OR ends_at >= ?)", now).
		Where("(tenant_id IS NULL OR tenant_id = ?)", tenantID).
		Order("priority DESC").Limit(5).
		Find(&banners)

	result := make([]BannerConfig, len(banners))
	for i, b := range banners {
		result[i] = BannerConfig{
			ID:       b.ID,
			Title:    b.Title,
			Subtitle: b.Subtitle,
			ImageURL: b.ImageURL,
			BgColor:  b.BgColor,
			TextColor: b.TextColor,
		}
		if b.ActionType != "" && b.ActionType != "none" {
			result[i].Action = &SDUIAction{Type: b.ActionType, Route: b.ActionValue}
		}
	}
	return result
}

func (h *SDUIHandler) getActiveAnnouncement(tenantID string) *AnnouncementConfig {
	now := time.Now()
	var banner AppBanner

	err := h.db.Where("is_active = ? AND priority >= 100", true).
		Where("(starts_at IS NULL OR starts_at <= ?)", now).
		Where("(ends_at IS NULL OR ends_at >= ?)", now).
		Where("(tenant_id IS NULL OR tenant_id = ?)", tenantID).
		Order("priority DESC").First(&banner).Error

	if err != nil {
		return nil
	}

	ann := &AnnouncementConfig{
		ID:          banner.ID,
		Type:        "banner",
		Title:       banner.Title,
		Body:        banner.Subtitle,
		ImageURL:    banner.ImageURL,
		BgColor:     banner.BgColor,
		TextColor:   banner.TextColor,
		Dismissible: true,
	}

	if banner.EndsAt != nil {
		ann.ShowUntil = banner.EndsAt.Format(time.RFC3339)
	}

	return ann
}

// HelpRequest model
type HelpRequest struct {
	ID        string    `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	UserID    string    `json:"user_id" gorm:"type:uuid;not null;index"`
	TenantID  string    `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID    *string   `json:"shop_id,omitempty" gorm:"type:uuid"`
	Screen    string    `json:"screen,omitempty"`    // which screen user was on
	Message   string    `json:"message,omitempty"`   // optional message
	Status    string    `json:"status" gorm:"default:'pending'"` // pending, acknowledged, resolved
	Priority  string    `json:"priority" gorm:"default:'normal'"` // low, normal, high, urgent
	Metadata  json.RawMessage `json:"metadata,omitempty" gorm:"type:jsonb"` // device info, app version, etc.
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (HelpRequest) TableName() string { return "help_requests" }

// AnalyticsEvent model
type AnalyticsEvent struct {
	ID        string          `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	UserID    string          `json:"user_id" gorm:"type:uuid;not null;index"`
	TenantID  string          `json:"tenant_id" gorm:"type:uuid;not null;index"`
	EventType string          `json:"event_type" gorm:"not null;index"` // screen_view, button_tap, api_call, error, help_request
	EventName string          `json:"event_name" gorm:"not null"`
	Screen    string          `json:"screen,omitempty"`
	Data      json.RawMessage `json:"data,omitempty" gorm:"type:jsonb"`
	SessionID string          `json:"session_id,omitempty" gorm:"index"`
	DeviceInfo json.RawMessage `json:"device_info,omitempty" gorm:"type:jsonb"`
	AppVersion string         `json:"app_version,omitempty"`
	Timestamp time.Time       `json:"timestamp" gorm:"index"`
	CreatedAt time.Time       `json:"created_at"`
}

func (AnalyticsEvent) TableName() string { return "analytics_events" }

// RequestHelp handles 1-click help requests
func (h *SDUIHandler) RequestHelp(c *gin.Context) {
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")

	var req struct {
		Screen  string          `json:"screen"`
		Message string          `json:"message"`
		Priority string         `json:"priority"`
		Metadata json.RawMessage `json:"metadata"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		// Allow empty body for 1-click help
		req.Priority = "normal"
	}

	if req.Priority == "" {
		req.Priority = "normal"
	}

	helpReq := HelpRequest{
		UserID:   userID,
		TenantID: tenantID,
		Screen:   req.Screen,
		Message:  req.Message,
		Status:   "pending",
		Priority: req.Priority,
		Metadata: req.Metadata,
	}

	if err := h.db.Create(&helpReq).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create help request"})
		return
	}

	// TODO: Send real-time notification to admin/support via WebSocket
	h.logger.Info("Help request created",
		zap.String("user_id", userID),
		zap.String("screen", req.Screen),
		zap.String("priority", req.Priority))

	c.JSON(http.StatusOK, gin.H{
		"success":    true,
		"request_id": helpReq.ID,
		"message":    "Help is on the way! Our team has been notified.",
	})
}

// TrackEvents handles batch analytics events
func (h *SDUIHandler) TrackEvents(c *gin.Context) {
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")

	var req struct {
		Events []struct {
			EventType  string          `json:"event_type"`
			EventName  string          `json:"event_name"`
			Screen     string          `json:"screen,omitempty"`
			Data       json.RawMessage `json:"data,omitempty"`
			SessionID  string          `json:"session_id,omitempty"`
			DeviceInfo json.RawMessage `json:"device_info,omitempty"`
			AppVersion string          `json:"app_version,omitempty"`
			Timestamp  time.Time       `json:"timestamp"`
		} `json:"events"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid event data"})
		return
	}

	// Batch insert events
	events := make([]AnalyticsEvent, len(req.Events))
	for i, e := range req.Events {
		ts := e.Timestamp
		if ts.IsZero() {
			ts = time.Now()
		}
		events[i] = AnalyticsEvent{
			UserID:     userID,
			TenantID:   tenantID,
			EventType:  e.EventType,
			EventName:  e.EventName,
			Screen:     e.Screen,
			Data:       e.Data,
			SessionID:  e.SessionID,
			DeviceInfo: e.DeviceInfo,
			AppVersion: e.AppVersion,
			Timestamp:  ts,
		}
	}

	if len(events) > 0 {
		h.db.CreateInBatches(events, 100)
	}

	c.JSON(http.StatusOK, gin.H{"accepted": len(events)})
}

// GetHelpRequests returns help requests for admin
func (h *SDUIHandler) GetHelpRequests(c *gin.Context) {
	tenantID := c.GetString("tenant_id")
	status := c.DefaultQuery("status", "pending")

	var requests []HelpRequest
	query := h.db.Where("tenant_id = ?", tenantID)
	if status != "all" {
		query = query.Where("status = ?", status)
	}
	query.Order("created_at DESC").Limit(50).Find(&requests)

	c.JSON(http.StatusOK, gin.H{"requests": requests})
}

// UpdateHelpRequest updates help request status
func (h *SDUIHandler) UpdateHelpRequest(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Status string `json:"status"` // acknowledged, resolved
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status is required"})
		return
	}

	h.db.Model(&HelpRequest{}).Where("id = ?", id).Update("status", req.Status)
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// getRoleOptionsForUser returns role options that the current user can create
func (h *SDUIHandler) getRoleOptionsForUser(role string) []map[string]interface{} {
	allRoles := []map[string]interface{}{
		{"value": "salesman", "label": "Salesman", "level": 10},
		{"value": "executive", "label": "Executive", "level": 30},
		{"value": "assistant_manager", "label": "Assistant Manager", "level": 50},
		{"value": "manager", "label": "Manager", "level": 70},
	}

	levels := map[string]int{
		"salesman": 10, "executive": 30, "assistant_manager": 50,
		"manager": 70, "admin": 90, "owner": 90, "saas_admin": 100,
	}

	currentLevel := levels[role]
	var result []map[string]interface{}
	for _, r := range allRoles {
		if r["level"].(int) < currentLevel {
			result = append(result, map[string]interface{}{"value": r["value"], "label": r["label"]})
		}
	}
	return result
}

func (h *SDUIHandler) getScreenForRole(screenID, role, tenantID string) *SDUIWidget {
	// First check DB for custom screen config
	var config SDUIScreenConfig
	err := h.db.Where("screen_id = ? AND is_active = ?", screenID, true).
		Where("(role = ? OR role = '*')", role).
		Where("(tenant_id IS NULL OR tenant_id = ?)", tenantID).
		Order("CASE WHEN tenant_id IS NOT NULL THEN 0 ELSE 1 END, CASE WHEN role != '*' THEN 0 ELSE 1 END").
		First(&config).Error

	if err == nil {
		var widget SDUIWidget
		if json.Unmarshal(config.Config, &widget) == nil {
			return &widget
		}
	}

	// Fall back to hardcoded screens
	screens := h.getScreens(role, tenantID)
	if screen, ok := screens[screenID]; ok {
		return &screen
	}

	return nil
}

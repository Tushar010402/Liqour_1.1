package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// ============================================================================
// APP LOG SESSION - Tracks user sessions for grouping logs
// ============================================================================

// AppLogSession represents a user session from the Flutter app
type AppLogSession struct {
	ID           uuid.UUID  `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID     uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null;index"`
	UserID       *uuid.UUID `json:"user_id,omitempty" gorm:"type:uuid;index"`
	DeviceID     string     `json:"device_id" gorm:"type:text;not null"`
	DeviceModel  string     `json:"device_model,omitempty" gorm:"type:text"`
	OSVersion    string     `json:"os_version,omitempty" gorm:"type:text"`
	AppVersion   string     `json:"app_version,omitempty" gorm:"type:text"`
	StartedAt    time.Time  `json:"started_at" gorm:"not null"`
	EndedAt      *time.Time `json:"ended_at,omitempty"`
	LogCount     int        `json:"log_count" gorm:"default:0"`
	ErrorCount   int        `json:"error_count" gorm:"default:0"`
	WarningCount int        `json:"warning_count" gorm:"default:0"`
	IsSynced     bool       `json:"is_synced" gorm:"default:false"`
	LastSyncAt   *time.Time `json:"last_sync_at,omitempty"`
	CreatedAt    time.Time  `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt    time.Time  `json:"updated_at" gorm:"autoUpdateTime"`

	// Relations
	LogEntries      []AppLogEntry       `json:"log_entries,omitempty" gorm:"foreignKey:SessionID"`
	NetworkRequests []AppNetworkRequest `json:"network_requests,omitempty" gorm:"foreignKey:SessionID"`
}

func (AppLogSession) TableName() string {
	return "app_log_sessions"
}

// ============================================================================
// APP LOG ENTRY - Individual log entries from the Flutter app
// ============================================================================

// AppLogEntry represents a single log entry from the Flutter app
type AppLogEntry struct {
	ID          uuid.UUID       `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	SessionID   *uuid.UUID      `json:"session_id,omitempty" gorm:"type:uuid;index"`
	TenantID    uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ClientLogID string          `json:"client_log_id,omitempty" gorm:"type:text;index"` // For deduplication
	Timestamp   time.Time       `json:"timestamp" gorm:"not null;index"`
	Level       string          `json:"level" gorm:"type:text;not null;index"`   // debug, info, warning, error, success
	Tag         string          `json:"tag" gorm:"type:text;not null;index"`     // API, Navigation, Error, etc.
	Message     string          `json:"message" gorm:"type:text;not null"`
	StackTrace  string          `json:"stack_trace,omitempty" gorm:"type:text"`
	Metadata    json.RawMessage `json:"metadata,omitempty" gorm:"type:jsonb"`
	ScreenName  string          `json:"screen_name,omitempty" gorm:"type:text"`
	CreatedAt   time.Time       `json:"created_at" gorm:"autoCreateTime"`

	// Relations
	Session        *AppLogSession     `json:"session,omitempty" gorm:"foreignKey:SessionID"`
	NetworkRequest *AppNetworkRequest `json:"network_request,omitempty" gorm:"foreignKey:LogEntryID"`
}

func (AppLogEntry) TableName() string {
	return "app_log_entries"
}

// LogLevel constants
const (
	LogLevelDebug   = "debug"
	LogLevelInfo    = "info"
	LogLevelWarning = "warning"
	LogLevelError   = "error"
	LogLevelSuccess = "success"
)

// LogTag constants
const (
	LogTagAPI        = "API"
	LogTagNavigation = "Navigation"
	LogTagError      = "Error"
	LogTagUserAction = "UserAction"
	LogTagLifecycle  = "Lifecycle"
	LogTagStorage    = "Storage"
	LogTagNetwork    = "Network"
)

// ============================================================================
// APP NETWORK REQUEST - Detailed API call logs
// ============================================================================

// AppNetworkRequest represents a network request log entry
type AppNetworkRequest struct {
	ID              uuid.UUID       `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	LogEntryID      *uuid.UUID      `json:"log_entry_id,omitempty" gorm:"type:uuid;index"`
	SessionID       *uuid.UUID      `json:"session_id,omitempty" gorm:"type:uuid;index"`
	TenantID        uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null;index"`
	RequestID       string          `json:"request_id,omitempty" gorm:"type:text"` // Correlation ID
	Method          string          `json:"method" gorm:"type:text;not null"`      // GET, POST, PUT, DELETE
	URL             string          `json:"url" gorm:"type:text;not null"`
	Path            string          `json:"path,omitempty" gorm:"type:text;index"`
	StatusCode      int             `json:"status_code,omitempty" gorm:"index"`
	DurationMs      int             `json:"duration_ms,omitempty" gorm:"index"`
	RequestSize     int             `json:"request_size,omitempty"`
	ResponseSize    int             `json:"response_size,omitempty"`
	RequestHeaders  json.RawMessage `json:"request_headers,omitempty" gorm:"type:jsonb"`
	ResponseHeaders json.RawMessage `json:"response_headers,omitempty" gorm:"type:jsonb"`
	ErrorMessage    string          `json:"error_message,omitempty" gorm:"type:text"`
	IsSuccess       bool            `json:"is_success" gorm:"default:true"`
	CreatedAt       time.Time       `json:"created_at" gorm:"autoCreateTime"`

	// Relations
	LogEntry *AppLogEntry   `json:"log_entry,omitempty" gorm:"foreignKey:LogEntryID"`
	Session  *AppLogSession `json:"session,omitempty" gorm:"foreignKey:SessionID"`
}

func (AppNetworkRequest) TableName() string {
	return "app_network_requests"
}

// ============================================================================
// APP LOG BATCH - Track received log batches
// ============================================================================

// AppLogBatch tracks received log batches for deduplication and audit
type AppLogBatch struct {
	ID           uuid.UUID  `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	BatchID      string     `json:"batch_id" gorm:"type:text;not null;uniqueIndex"` // ID from Flutter app
	SessionID    *uuid.UUID `json:"session_id,omitempty" gorm:"type:uuid;index"`
	TenantID     uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null;index"`
	LogCount     int        `json:"log_count" gorm:"not null"`
	ReceivedAt   time.Time  `json:"received_at" gorm:"default:now()"`
	ProcessedAt  *time.Time `json:"processed_at,omitempty"`
	Status       string     `json:"status" gorm:"type:text;default:'received'"` // received, processed, failed
	ErrorMessage string     `json:"error_message,omitempty" gorm:"type:text"`
	CreatedAt    time.Time  `json:"created_at" gorm:"autoCreateTime"`

	// Relations
	Session *AppLogSession `json:"session,omitempty" gorm:"foreignKey:SessionID"`
}

func (AppLogBatch) TableName() string {
	return "app_log_batches"
}

// Batch status constants
const (
	BatchStatusReceived  = "received"
	BatchStatusProcessed = "processed"
	BatchStatusFailed    = "failed"
)

// ============================================================================
// REQUEST/RESPONSE DTOs for API
// ============================================================================

// LogBatchRequest represents the request body for POST /api/logs/batch
type LogBatchRequest struct {
	BatchID string            `json:"batch_id" binding:"required"`
	Device  LogDeviceInfo     `json:"device" binding:"required"`
	Session LogSessionInfo    `json:"session" binding:"required"`
	Logs    []LogEntryRequest `json:"logs" binding:"required"`
}

// LogDeviceInfo contains device information
type LogDeviceInfo struct {
	ID         string `json:"id" binding:"required"`
	Model      string `json:"model,omitempty"`
	OS         string `json:"os,omitempty"`
	AppVersion string `json:"app_version,omitempty"`
}

// LogSessionInfo contains session information
type LogSessionInfo struct {
	ID        string `json:"id" binding:"required"`
	StartedAt string `json:"started_at" binding:"required"`
	UserID    string `json:"user_id,omitempty"`
	TenantID  string `json:"tenant_id,omitempty"`
}

// LogEntryRequest represents a single log entry in the batch request
type LogEntryRequest struct {
	ID         string                 `json:"id" binding:"required"`
	Timestamp  string                 `json:"timestamp" binding:"required"`
	Level      string                 `json:"level" binding:"required"`
	Tag        string                 `json:"tag" binding:"required"`
	Message    string                 `json:"message" binding:"required"`
	StackTrace string                 `json:"stack_trace,omitempty"`
	ScreenName string                 `json:"screen_name,omitempty"`
	Metadata   map[string]interface{} `json:"metadata,omitempty"`
}

// LogBatchResponse represents the response for POST /api/logs/batch
type LogBatchResponse struct {
	Success   bool      `json:"success"`
	Received  int       `json:"received"`
	SessionID uuid.UUID `json:"session_id"`
	BatchID   string    `json:"batch_id"`
}

// LogSessionsResponse represents the response for GET /api/logs/sessions
type LogSessionsResponse struct {
	Sessions []AppLogSession `json:"sessions"`
	Total    int64           `json:"total"`
	Page     int             `json:"page"`
	PageSize int             `json:"page_size"`
}

// LogEntriesResponse represents the response for GET /api/logs
type LogEntriesResponse struct {
	Logs     []AppLogEntry `json:"logs"`
	Total    int64         `json:"total"`
	Page     int           `json:"page"`
	PageSize int           `json:"page_size"`
}

// LogStatsResponse represents the response for GET /api/logs/stats
type LogStatsResponse struct {
	TotalLogs          int64            `json:"total_logs"`
	TotalSessions      int64            `json:"total_sessions"`
	ActiveSessions     int64            `json:"active_sessions"`
	LogsByLevel        map[string]int64 `json:"by_level"`
	LogsByTag          map[string]int64 `json:"by_tag"`
	ErrorRate          float64          `json:"error_rate"`
	AvgSessionDuration string           `json:"avg_session_duration"`
	TopErrors          []ErrorSummary   `json:"top_errors,omitempty"`
}

// ErrorSummary represents a summarized error
type ErrorSummary struct {
	Message string `json:"message"`
	Count   int64  `json:"count"`
	LastAt  string `json:"last_at"`
}

// NetworkRequestsResponse represents the response for GET /api/logs/network
type NetworkRequestsResponse struct {
	Requests []AppNetworkRequest `json:"requests"`
	Total    int64               `json:"total"`
	Page     int                 `json:"page"`
	PageSize int                 `json:"page_size"`
}

// LogQueryParams represents query parameters for log endpoints
type LogQueryParams struct {
	TenantID  string `form:"tenant_id"`
	SessionID string `form:"session_id"`
	UserID    string `form:"user_id"`
	Level     string `form:"level"`
	Tag       string `form:"tag"`
	Search    string `form:"search"`
	From      string `form:"from"`
	To        string `form:"to"`
	Page      int    `form:"page,default=1"`
	PageSize  int    `form:"page_size,default=50"`
	Grouped   bool   `form:"grouped"` // When true, return aggregated/grouped results
}

// GroupedLogEntry represents aggregated log entries with same message pattern
type GroupedLogEntry struct {
	Level       string    `json:"level"`
	Tag         string    `json:"tag"`
	BaseMessage string    `json:"base_message"` // Message pattern without dynamic parts
	Count       int       `json:"count"`
	LastTime    time.Time `json:"last_time"`
	FirstTime   time.Time `json:"first_time"`
}

// GroupedNetworkRequest represents aggregated network requests by endpoint
type GroupedNetworkRequest struct {
	Method       string    `json:"method"`
	Endpoint     string    `json:"endpoint"`
	Count        int       `json:"count"`
	SuccessCount int       `json:"success_count"`
	ErrorCount   int       `json:"error_count"`
	AvgDuration  int       `json:"avg_duration_ms"`
	MinDuration  int       `json:"min_duration_ms"`
	MaxDuration  int       `json:"max_duration_ms"`
	LastTime     time.Time `json:"last_time"`
	LastStatus   int       `json:"last_status"`
}

// GroupedLogEntriesResponse is the response for grouped log queries
type GroupedLogEntriesResponse struct {
	Groups     []GroupedLogEntry `json:"groups"`
	TotalLogs  int64             `json:"total_logs"`
	TotalGroups int              `json:"total_groups"`
}

// GroupedNetworkRequestsResponse is the response for grouped network queries
type GroupedNetworkRequestsResponse struct {
	Groups        []GroupedNetworkRequest `json:"groups"`
	TotalRequests int64                   `json:"total_requests"`
	TotalGroups   int                     `json:"total_groups"`
}

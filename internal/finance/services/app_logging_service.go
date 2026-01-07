package services

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// ============================================================================
// ROLE-BASED ACCESS CONTROL
// ============================================================================

// LogAccessParams contains role-based access control parameters for log queries
type LogAccessParams struct {
	TenantID       uuid.UUID  // User's tenant (uuid.Nil for saas_admin)
	UserID         uuid.UUID  // Current user's ID
	Role           string     // Current user's role
	FilterUserID   *uuid.UUID // Optional: filter by specific user
	FilterTenantID *uuid.UUID // Optional: filter by tenant (saas_admin only)
}

// CanViewAllTenants returns true if the user can view logs across all tenants
func (p *LogAccessParams) CanViewAllTenants() bool {
	return p.Role == models.RoleSaasAdmin
}

// CanViewAllUsersInTenant returns true if the user can view all users' logs within their tenant
func (p *LogAccessParams) CanViewAllUsersInTenant() bool {
	return p.Role == models.RoleAdmin || p.Role == models.RoleOwner || p.Role == models.RoleSaasAdmin
}

// CanViewHierarchicalUsers returns true if user can view lower-role users
func (p *LogAccessParams) CanViewHierarchicalUsers() bool {
	return p.Role == models.RoleAssistantManager || p.Role == models.RoleManager
}

// MustViewOwnLogsOnly returns true if user can only see their own logs
func (p *LogAccessParams) MustViewOwnLogsOnly() bool {
	return p.Role == models.RoleSalesman || p.Role == models.RoleExecutive
}

// LogUserInfo represents minimal user info for dropdown selection
type LogUserInfo struct {
	ID       uuid.UUID `json:"id"`
	Username string    `json:"username"`
	FullName string    `json:"full_name"`
	Role     string    `json:"role"`
}

// AppLoggingService handles app log storage and retrieval
type AppLoggingService struct {
	db     *database.DB
	logger *zap.Logger
}

// NewAppLoggingService creates a new app logging service
func NewAppLoggingService(db *database.DB, logger *zap.Logger) *AppLoggingService {
	return &AppLoggingService{
		db:     db,
		logger: logger,
	}
}

// ============================================================================
// ACCESS CONTROL METHODS
// ============================================================================

// TableType indicates which table is being queried for proper filtering
type TableType string

const (
	TableSessions TableType = "sessions" // app_log_sessions - has user_id directly
	TableEntries  TableType = "entries"  // app_log_entries - no user_id, needs session join
	TableNetwork  TableType = "network"  // app_network_requests - no user_id, needs session join
)

// applyUserAccessFilter applies role-based user filtering to a GORM query
// This method modifies the query based on the user's role and access permissions
func (s *AppLoggingService) applyUserAccessFilter(query *gorm.DB, params *LogAccessParams) *gorm.DB {
	return s.applyUserAccessFilterForTable(query, params, TableSessions)
}

// applyUserAccessFilterForTable applies role-based filtering with table-specific user_id handling
// For sessions table: filters user_id directly
// For entries/network tables: uses subquery via session_id since they don't have user_id column
func (s *AppLoggingService) applyUserAccessFilterForTable(query *gorm.DB, params *LogAccessParams, tableType TableType) *gorm.DB {
	// Helper to apply user filter based on table type
	applyUserFilter := func(q *gorm.DB, userID uuid.UUID) *gorm.DB {
		if tableType == TableSessions {
			return q.Where("user_id = ?", userID)
		}
		// For entries and network, use subquery via session_id
		return q.Where(`session_id IN (
			SELECT id FROM app_log_sessions
			WHERE user_id = ? AND tenant_id = tenant_id
		)`, userID)
	}

	// Helper to apply hierarchical user filter
	applyHierarchicalFilter := func(q *gorm.DB, tenantID uuid.UUID, allowedRoles []string) *gorm.DB {
		if tableType == TableSessions {
			return q.Where(`user_id IN (
				SELECT id FROM users
				WHERE tenant_id = ? AND role IN ? AND deleted_at IS NULL
			)`, tenantID, allowedRoles)
		}
		// For entries and network, use nested subquery via session_id
		return q.Where(`session_id IN (
			SELECT id FROM app_log_sessions
			WHERE tenant_id = ? AND user_id IN (
				SELECT id FROM users
				WHERE tenant_id = ? AND role IN ? AND deleted_at IS NULL
			)
		)`, tenantID, tenantID, allowedRoles)
	}

	// SaaS Admin: can optionally filter by tenant
	if params.CanViewAllTenants() {
		if params.FilterTenantID != nil && *params.FilterTenantID != uuid.Nil {
			query = query.Where("tenant_id = ?", *params.FilterTenantID)
		}
		// Optionally filter by specific user
		if params.FilterUserID != nil && *params.FilterUserID != uuid.Nil {
			query = applyUserFilter(query, *params.FilterUserID)
		}
		return query
	}

	// All other roles: must be scoped to their tenant
	query = query.Where("tenant_id = ?", params.TenantID)

	// Tenant Admins (admin, owner): can see all users in tenant
	if params.CanViewAllUsersInTenant() {
		if params.FilterUserID != nil && *params.FilterUserID != uuid.Nil {
			query = applyUserFilter(query, *params.FilterUserID)
		}
		return query
	}

	// Managers (assistant_manager, manager): can see hierarchical users
	if params.CanViewHierarchicalUsers() {
		if params.FilterUserID != nil && *params.FilterUserID != uuid.Nil {
			// Manager specified a user - filter directly
			query = applyUserFilter(query, *params.FilterUserID)
		} else {
			// No specific user - show all viewable users based on role hierarchy
			allowedRoles := utils.GetAllowedRoles(params.Role)
			if len(allowedRoles) > 0 {
				query = applyHierarchicalFilter(query, params.TenantID, allowedRoles)
			}
		}
		return query
	}

	// Regular users (salesman, executive): own logs only
	query = applyUserFilter(query, params.UserID)
	return query
}

// GetViewableUsers returns list of users whose logs the current user can view
func (s *AppLoggingService) GetViewableUsers(ctx context.Context, params *LogAccessParams) ([]LogUserInfo, error) {
	// Regular users can only see themselves
	if params.MustViewOwnLogsOnly() {
		// Query just the current user
		type userRow struct {
			ID        uuid.UUID
			Username  string
			FirstName string
			LastName  string
			Role      string
		}
		var user userRow
		err := s.db.DB.WithContext(ctx).
			Table("users").
			Select("id, username, first_name, last_name, role").
			Where("id = ?", params.UserID).
			First(&user).Error
		if err != nil {
			return nil, fmt.Errorf("failed to get current user: %w", err)
		}

		return []LogUserInfo{{
			ID:       user.ID,
			Username: user.Username,
			FullName: strings.TrimSpace(user.FirstName + " " + user.LastName),
			Role:     user.Role,
		}}, nil
	}

	query := s.db.DB.WithContext(ctx).Table("users").
		Select("id, username, first_name, last_name, role").
		Where("deleted_at IS NULL AND is_active = true")

	// SaaS Admin viewing specific tenant
	if params.CanViewAllTenants() {
		if params.FilterTenantID != nil && *params.FilterTenantID != uuid.Nil {
			query = query.Where("tenant_id = ?", *params.FilterTenantID)
		}
		// If no tenant specified, don't filter by tenant (show all)
	} else {
		// All other users: scope to tenant
		query = query.Where("tenant_id = ?", params.TenantID)

		// Managers: filter by allowed roles
		if params.CanViewHierarchicalUsers() {
			allowedRoles := utils.GetAllowedRoles(params.Role)
			if len(allowedRoles) > 0 {
				query = query.Where("role IN ?", allowedRoles)
			}
		}
		// Tenant admins: no additional filtering (see all in tenant)
	}

	query = query.Order("first_name, last_name")

	type userRow struct {
		ID        uuid.UUID
		Username  string
		FirstName string
		LastName  string
		Role      string
	}
	var rows []userRow

	if err := query.Find(&rows).Error; err != nil {
		return nil, fmt.Errorf("failed to get viewable users: %w", err)
	}

	users := make([]LogUserInfo, len(rows))
	for i, row := range rows {
		users[i] = LogUserInfo{
			ID:       row.ID,
			Username: row.Username,
			FullName: strings.TrimSpace(row.FirstName + " " + row.LastName),
			Role:     row.Role,
		}
	}

	return users, nil
}

// ============================================================================
// BATCH LOG PROCESSING
// ============================================================================

// ProcessLogBatch processes an incoming batch of logs from the Flutter app
// authUserID is the authenticated user from the request context (used as fallback if session doesn't specify user)
func (s *AppLoggingService) ProcessLogBatch(ctx context.Context, req *models.LogBatchRequest, tenantID uuid.UUID, authUserID *uuid.UUID) (*models.LogBatchResponse, error) {
	// Parse session info
	sessionUUID, err := uuid.Parse(req.Session.ID)
	if err != nil {
		sessionUUID = uuid.New()
	}

	// Parse started_at
	startedAt, err := time.Parse(time.RFC3339, req.Session.StartedAt)
	if err != nil {
		startedAt = time.Now()
	}

	// Parse user ID if provided in session, otherwise use authenticated user
	var userID *uuid.UUID
	if req.Session.UserID != "" {
		if uid, err := uuid.Parse(req.Session.UserID); err == nil {
			userID = &uid
		}
	}
	// Fallback to authenticated user if session doesn't specify one
	if userID == nil && authUserID != nil {
		userID = authUserID
	}

	// Check if batch already exists (deduplication)
	var existingBatch models.AppLogBatch
	if err := s.db.DB.WithContext(ctx).
		Where("batch_id = ?", req.BatchID).
		First(&existingBatch).Error; err == nil {
		// Batch already processed, return success with existing data
		return &models.LogBatchResponse{
			Success:   true,
			Received:  existingBatch.LogCount,
			SessionID: *existingBatch.SessionID,
			BatchID:   existingBatch.BatchID,
		}, nil
	}

	// Start transaction
	tx := s.db.DB.WithContext(ctx).Begin()
	if tx.Error != nil {
		return nil, fmt.Errorf("failed to start transaction: %w", tx.Error)
	}
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// Create or update session
	session := models.AppLogSession{
		ID:          sessionUUID,
		TenantID:    tenantID,
		UserID:      userID,
		DeviceID:    req.Device.ID,
		DeviceModel: req.Device.Model,
		OSVersion:   req.Device.OS,
		AppVersion:  req.Device.AppVersion,
		StartedAt:   startedAt,
		IsSynced:    true,
		LastSyncAt:  timePtr(time.Now()),
	}

	// Upsert session
	if err := tx.Clauses().
		Where("id = ?", sessionUUID).
		Assign(models.AppLogSession{
			DeviceModel: session.DeviceModel,
			OSVersion:   session.OSVersion,
			AppVersion:  session.AppVersion,
			IsSynced:    true,
			LastSyncAt:  session.LastSyncAt,
		}).
		FirstOrCreate(&session).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create/update session: %w", err)
	}

	// Count errors and warnings in this batch
	errorCount := 0
	warningCount := 0
	logEntries := make([]models.AppLogEntry, 0, len(req.Logs))
	networkRequests := make([]models.AppNetworkRequest, 0)

	// Process each log entry
	for _, logReq := range req.Logs {
		// Parse timestamp
		timestamp, err := time.Parse(time.RFC3339, logReq.Timestamp)
		if err != nil {
			timestamp = time.Now()
		}

		// Convert metadata to JSON
		var metadata json.RawMessage
		if logReq.Metadata != nil {
			if metaBytes, err := json.Marshal(logReq.Metadata); err == nil {
				metadata = metaBytes
			}
		}

		entry := models.AppLogEntry{
			ID:          uuid.New(),
			SessionID:   &sessionUUID,
			TenantID:    tenantID,
			ClientLogID: logReq.ID,
			Timestamp:   timestamp,
			Level:       strings.ToLower(logReq.Level),
			Tag:         logReq.Tag,
			Message:     logReq.Message,
			StackTrace:  logReq.StackTrace,
			ScreenName:  logReq.ScreenName,
			Metadata:    metadata,
		}

		logEntries = append(logEntries, entry)

		// Count by level
		switch strings.ToLower(logReq.Level) {
		case models.LogLevelError:
			errorCount++
		case models.LogLevelWarning:
			warningCount++
		}

		// Extract network request if metadata contains it
		if logReq.Tag == models.LogTagAPI && logReq.Metadata != nil {
			if networkReq := s.extractNetworkRequest(logReq.Metadata, &entry.ID, &sessionUUID, tenantID); networkReq != nil {
				networkRequests = append(networkRequests, *networkReq)
			}
		}
	}

	// Batch insert log entries
	if len(logEntries) > 0 {
		if err := tx.CreateInBatches(logEntries, 100).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to insert log entries: %w", err)
		}
	}

	// Batch insert network requests
	if len(networkRequests) > 0 {
		if err := tx.CreateInBatches(networkRequests, 100).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to insert network requests: %w", err)
		}
	}

	// Update session counts
	if err := tx.Model(&models.AppLogSession{}).
		Where("id = ?", sessionUUID).
		Updates(map[string]interface{}{
			"log_count":     gorm.Expr("log_count + ?", len(logEntries)),
			"error_count":   gorm.Expr("error_count + ?", errorCount),
			"warning_count": gorm.Expr("warning_count + ?", warningCount),
		}).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to update session counts: %w", err)
	}

	// Create batch record
	batch := models.AppLogBatch{
		BatchID:     req.BatchID,
		SessionID:   &sessionUUID,
		TenantID:    tenantID,
		LogCount:    len(logEntries),
		ReceivedAt:  time.Now(),
		ProcessedAt: timePtr(time.Now()),
		Status:      models.BatchStatusProcessed,
	}
	if err := tx.Create(&batch).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create batch record: %w", err)
	}

	// Commit transaction
	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	s.logger.Info("Processed log batch",
		zap.String("batch_id", req.BatchID),
		zap.String("session_id", sessionUUID.String()),
		zap.Int("log_count", len(logEntries)),
		zap.Int("error_count", errorCount),
	)

	return &models.LogBatchResponse{
		Success:   true,
		Received:  len(logEntries),
		SessionID: sessionUUID,
		BatchID:   req.BatchID,
	}, nil
}

// extractNetworkRequest extracts network request details from metadata
func (s *AppLoggingService) extractNetworkRequest(metadata map[string]interface{}, logEntryID, sessionID *uuid.UUID, tenantID uuid.UUID) *models.AppNetworkRequest {
	req := &models.AppNetworkRequest{
		ID:         uuid.New(),
		LogEntryID: logEntryID,
		SessionID:  sessionID,
		TenantID:   tenantID,
		IsSuccess:  true,
	}

	// Extract method
	if method, ok := metadata["method"].(string); ok {
		req.Method = method
	} else {
		return nil // Method is required
	}

	// Extract URL
	if url, ok := metadata["url"].(string); ok {
		req.URL = url
		// Extract path
		if idx := strings.Index(url, "/api/"); idx >= 0 {
			req.Path = url[idx:]
		}
	} else if endpoint, ok := metadata["endpoint"].(string); ok {
		req.URL = endpoint
		req.Path = endpoint
	} else {
		return nil // URL is required
	}

	// Extract optional fields
	if statusCode, ok := metadata["status_code"].(float64); ok {
		req.StatusCode = int(statusCode)
		if req.StatusCode >= 400 {
			req.IsSuccess = false
		}
	}
	if durationMs, ok := metadata["duration_ms"].(float64); ok {
		req.DurationMs = int(durationMs)
	}
	if requestID, ok := metadata["request_id"].(string); ok {
		req.RequestID = requestID
	}
	if errorMsg, ok := metadata["error"].(string); ok {
		req.ErrorMessage = errorMsg
		req.IsSuccess = false
	}

	return req
}

// ============================================================================
// QUERY METHODS
// ============================================================================

// GetSessions retrieves sessions with role-based access control
func (s *AppLoggingService) GetSessions(ctx context.Context, params *models.LogQueryParams, accessParams *LogAccessParams) (*models.LogSessionsResponse, error) {
	query := s.db.DB.WithContext(ctx).Model(&models.AppLogSession{})

	// Apply role-based access filtering
	if accessParams != nil {
		query = s.applyUserAccessFilter(query, accessParams)
	} else {
		// Legacy support: if no accessParams, use tenant/user from query params
		if params.TenantID != "" {
			if tenantUUID, err := uuid.Parse(params.TenantID); err == nil {
				query = query.Where("tenant_id = ?", tenantUUID)
			}
		}
		if params.UserID != "" {
			if userUUID, err := uuid.Parse(params.UserID); err == nil {
				query = query.Where("user_id = ?", userUUID)
			}
		}
	}

	// Apply date filters
	if params.From != "" {
		if from, err := time.Parse(time.RFC3339, params.From); err == nil {
			query = query.Where("started_at >= ?", from)
		}
	}
	if params.To != "" {
		if to, err := time.Parse(time.RFC3339, params.To); err == nil {
			query = query.Where("started_at <= ?", to)
		}
	}

	// Get total count
	var total int64
	if err := query.Count(&total).Error; err != nil {
		return nil, fmt.Errorf("failed to count sessions: %w", err)
	}

	// Pagination
	page := params.Page
	if page < 1 {
		page = 1
	}
	pageSize := params.PageSize
	if pageSize < 1 || pageSize > 100 {
		pageSize = 50
	}
	offset := (page - 1) * pageSize

	// Fetch sessions
	var sessions []models.AppLogSession
	if err := query.
		Order("started_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&sessions).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch sessions: %w", err)
	}

	return &models.LogSessionsResponse{
		Sessions: sessions,
		Total:    total,
		Page:     page,
		PageSize: pageSize,
	}, nil
}

// GetLogs retrieves log entries with role-based access control
func (s *AppLoggingService) GetLogs(ctx context.Context, params *models.LogQueryParams, accessParams *LogAccessParams) (*models.LogEntriesResponse, error) {
	query := s.db.DB.WithContext(ctx).Model(&models.AppLogEntry{})

	// Apply role-based access filtering (using TableEntries since app_log_entries has no user_id)
	if accessParams != nil {
		query = s.applyUserAccessFilterForTable(query, accessParams, TableEntries)
	} else {
		// Legacy support: if no accessParams, use tenant from query params
		if params.TenantID != "" {
			if tenantUUID, err := uuid.Parse(params.TenantID); err == nil {
				query = query.Where("tenant_id = ?", tenantUUID)
			}
		}
	}

	// Apply additional filters
	if params.SessionID != "" {
		if sessionUUID, err := uuid.Parse(params.SessionID); err == nil {
			query = query.Where("session_id = ?", sessionUUID)
		}
	}
	if params.Level != "" {
		query = query.Where("level = ?", strings.ToLower(params.Level))
	}
	if params.Tag != "" {
		query = query.Where("tag = ?", params.Tag)
	}
	if params.Search != "" {
		searchPattern := "%" + params.Search + "%"
		query = query.Where("message ILIKE ? OR tag ILIKE ?", searchPattern, searchPattern)
	}
	if params.From != "" {
		if from, err := time.Parse(time.RFC3339, params.From); err == nil {
			query = query.Where("timestamp >= ?", from)
		}
	}
	if params.To != "" {
		if to, err := time.Parse(time.RFC3339, params.To); err == nil {
			query = query.Where("timestamp <= ?", to)
		}
	}

	// Get total count
	var total int64
	if err := query.Count(&total).Error; err != nil {
		return nil, fmt.Errorf("failed to count logs: %w", err)
	}

	// Pagination
	page := params.Page
	if page < 1 {
		page = 1
	}
	pageSize := params.PageSize
	if pageSize < 1 || pageSize > 100 {
		pageSize = 50
	}
	offset := (page - 1) * pageSize

	// Fetch logs
	var logs []models.AppLogEntry
	if err := query.
		Order("timestamp DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&logs).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch logs: %w", err)
	}

	return &models.LogEntriesResponse{
		Logs:     logs,
		Total:    total,
		Page:     page,
		PageSize: pageSize,
	}, nil
}

// GetNetworkRequests retrieves network request logs with role-based access control
func (s *AppLoggingService) GetNetworkRequests(ctx context.Context, params *models.LogQueryParams, accessParams *LogAccessParams) (*models.NetworkRequestsResponse, error) {
	query := s.db.DB.WithContext(ctx).Model(&models.AppNetworkRequest{})

	// Apply role-based access filtering (using TableNetwork since app_network_requests has no user_id)
	if accessParams != nil {
		query = s.applyUserAccessFilterForTable(query, accessParams, TableNetwork)
	} else {
		// Legacy support: if no accessParams, use tenant from query params
		if params.TenantID != "" {
			if tenantUUID, err := uuid.Parse(params.TenantID); err == nil {
				query = query.Where("tenant_id = ?", tenantUUID)
			}
		}
	}

	// Apply additional filters
	if params.SessionID != "" {
		if sessionUUID, err := uuid.Parse(params.SessionID); err == nil {
			query = query.Where("session_id = ?", sessionUUID)
		}
	}
	if params.From != "" {
		if from, err := time.Parse(time.RFC3339, params.From); err == nil {
			query = query.Where("created_at >= ?", from)
		}
	}
	if params.To != "" {
		if to, err := time.Parse(time.RFC3339, params.To); err == nil {
			query = query.Where("created_at <= ?", to)
		}
	}

	// Get total count
	var total int64
	if err := query.Count(&total).Error; err != nil {
		return nil, fmt.Errorf("failed to count network requests: %w", err)
	}

	// Pagination
	page := params.Page
	if page < 1 {
		page = 1
	}
	pageSize := params.PageSize
	if pageSize < 1 || pageSize > 100 {
		pageSize = 50
	}
	offset := (page - 1) * pageSize

	// Fetch requests
	var requests []models.AppNetworkRequest
	if err := query.
		Order("created_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&requests).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch network requests: %w", err)
	}

	return &models.NetworkRequestsResponse{
		Requests: requests,
		Total:    total,
		Page:     page,
		PageSize: pageSize,
	}, nil
}

// GetGroupedLogs retrieves aggregated log entries grouped by message pattern
func (s *AppLoggingService) GetGroupedLogs(ctx context.Context, params *models.LogQueryParams, accessParams *LogAccessParams) (*models.GroupedLogEntriesResponse, error) {
	// Build base query with access filtering
	baseQuery := s.db.DB.WithContext(ctx).Model(&models.AppLogEntry{})
	if accessParams != nil {
		baseQuery = s.applyUserAccessFilterForTable(baseQuery, accessParams, TableEntries)
	} else if params.TenantID != "" {
		if tenantUUID, err := uuid.Parse(params.TenantID); err == nil {
			baseQuery = baseQuery.Where("tenant_id = ?", tenantUUID)
		}
	}

	// Apply additional filters
	if params.SessionID != "" {
		if sessionUUID, err := uuid.Parse(params.SessionID); err == nil {
			baseQuery = baseQuery.Where("session_id = ?", sessionUUID)
		}
	}
	if params.Level != "" {
		baseQuery = baseQuery.Where("level = ?", strings.ToLower(params.Level))
	}
	if params.Tag != "" {
		baseQuery = baseQuery.Where("tag = ?", params.Tag)
	}
	if params.Search != "" {
		searchPattern := "%" + params.Search + "%"
		baseQuery = baseQuery.Where("message ILIKE ? OR tag ILIKE ?", searchPattern, searchPattern)
	}
	if params.From != "" {
		if from, err := time.Parse(time.RFC3339, params.From); err == nil {
			baseQuery = baseQuery.Where("timestamp >= ?", from)
		}
	}
	if params.To != "" {
		if to, err := time.Parse(time.RFC3339, params.To); err == nil {
			baseQuery = baseQuery.Where("timestamp <= ?", to)
		}
	}

	// Get total count
	var totalLogs int64
	if err := baseQuery.Count(&totalLogs).Error; err != nil {
		return nil, fmt.Errorf("failed to count logs: %w", err)
	}

	// Query for grouped results using PostgreSQL aggregation
	// We normalize the message by removing dynamic parts (status codes, durations)
	type groupResult struct {
		Level       string    `gorm:"column:level"`
		Tag         string    `gorm:"column:tag"`
		BaseMessage string    `gorm:"column:base_message"`
		Count       int       `gorm:"column:count"`
		LastTime    time.Time `gorm:"column:last_time"`
		FirstTime   time.Time `gorm:"column:first_time"`
	}

	var results []groupResult
	// Use regexp_replace to normalize messages by removing response codes and durations
	groupQuery := s.db.DB.WithContext(ctx).
		Table("(?) as filtered_logs", baseQuery).
		Select(`
			level,
			tag,
			regexp_replace(
				regexp_replace(message, '→\s*\d{3}\s*', '', 'g'),
				'\(\d+(\.\d+)?(ms|s)\)', '', 'g'
			) as base_message,
			COUNT(*) as count,
			MAX(timestamp) as last_time,
			MIN(timestamp) as first_time
		`).
		Group("level, tag, base_message").
		Order("last_time DESC").
		Limit(100) // Limit to top 100 groups

	if err := groupQuery.Find(&results).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch grouped logs: %w", err)
	}

	// Convert to response format
	groups := make([]models.GroupedLogEntry, len(results))
	for i, r := range results {
		groups[i] = models.GroupedLogEntry{
			Level:       r.Level,
			Tag:         r.Tag,
			BaseMessage: strings.TrimSpace(r.BaseMessage),
			Count:       r.Count,
			LastTime:    r.LastTime,
			FirstTime:   r.FirstTime,
		}
	}

	return &models.GroupedLogEntriesResponse{
		Groups:      groups,
		TotalLogs:   totalLogs,
		TotalGroups: len(groups),
	}, nil
}

// GetGroupedNetworkRequests retrieves aggregated network requests grouped by method+endpoint
func (s *AppLoggingService) GetGroupedNetworkRequests(ctx context.Context, params *models.LogQueryParams, accessParams *LogAccessParams) (*models.GroupedNetworkRequestsResponse, error) {
	// Build base query with access filtering
	baseQuery := s.db.DB.WithContext(ctx).Model(&models.AppNetworkRequest{})
	if accessParams != nil {
		baseQuery = s.applyUserAccessFilterForTable(baseQuery, accessParams, TableNetwork)
	} else if params.TenantID != "" {
		if tenantUUID, err := uuid.Parse(params.TenantID); err == nil {
			baseQuery = baseQuery.Where("tenant_id = ?", tenantUUID)
		}
	}

	// Apply additional filters
	if params.SessionID != "" {
		if sessionUUID, err := uuid.Parse(params.SessionID); err == nil {
			baseQuery = baseQuery.Where("session_id = ?", sessionUUID)
		}
	}
	if params.From != "" {
		if from, err := time.Parse(time.RFC3339, params.From); err == nil {
			baseQuery = baseQuery.Where("created_at >= ?", from)
		}
	}
	if params.To != "" {
		if to, err := time.Parse(time.RFC3339, params.To); err == nil {
			baseQuery = baseQuery.Where("created_at <= ?", to)
		}
	}

	// Get total count
	var totalRequests int64
	if err := baseQuery.Count(&totalRequests).Error; err != nil {
		return nil, fmt.Errorf("failed to count network requests: %w", err)
	}

	// Query for grouped results
	type groupResult struct {
		Method       string    `gorm:"column:method"`
		Endpoint     string    `gorm:"column:endpoint"`
		Count        int       `gorm:"column:count"`
		SuccessCount int       `gorm:"column:success_count"`
		ErrorCount   int       `gorm:"column:error_count"`
		AvgDuration  int       `gorm:"column:avg_duration"`
		MinDuration  int       `gorm:"column:min_duration"`
		MaxDuration  int       `gorm:"column:max_duration"`
		LastTime     time.Time `gorm:"column:last_time"`
		LastStatus   int       `gorm:"column:last_status"`
	}

	var results []groupResult
	groupQuery := s.db.DB.WithContext(ctx).
		Table("(?) as filtered_requests", baseQuery).
		Select(`
			method,
			COALESCE(path, url) as endpoint,
			COUNT(*) as count,
			SUM(CASE WHEN status_code >= 200 AND status_code < 400 THEN 1 ELSE 0 END) as success_count,
			SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) as error_count,
			COALESCE(AVG(NULLIF(duration_ms, 0)), 0)::int as avg_duration,
			COALESCE(MIN(NULLIF(duration_ms, 0)), 0) as min_duration,
			COALESCE(MAX(duration_ms), 0) as max_duration,
			MAX(created_at) as last_time,
			(array_agg(status_code ORDER BY created_at DESC))[1] as last_status
		`).
		Group("method, COALESCE(path, url)").
		Order("last_time DESC").
		Limit(100) // Limit to top 100 groups

	if err := groupQuery.Find(&results).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch grouped network requests: %w", err)
	}

	// Convert to response format
	groups := make([]models.GroupedNetworkRequest, len(results))
	for i, r := range results {
		groups[i] = models.GroupedNetworkRequest{
			Method:       r.Method,
			Endpoint:     r.Endpoint,
			Count:        r.Count,
			SuccessCount: r.SuccessCount,
			ErrorCount:   r.ErrorCount,
			AvgDuration:  r.AvgDuration,
			MinDuration:  r.MinDuration,
			MaxDuration:  r.MaxDuration,
			LastTime:     r.LastTime,
			LastStatus:   r.LastStatus,
		}
	}

	return &models.GroupedNetworkRequestsResponse{
		Groups:        groups,
		TotalRequests: totalRequests,
		TotalGroups:   len(groups),
	}, nil
}

// GetLogStats retrieves log statistics with role-based access control
func (s *AppLoggingService) GetLogStats(ctx context.Context, accessParams *LogAccessParams, period string) (*models.LogStatsResponse, error) {
	// Determine time range based on period
	var since time.Time
	switch period {
	case "1h":
		since = time.Now().Add(-1 * time.Hour)
	case "6h":
		since = time.Now().Add(-6 * time.Hour)
	case "24h":
		since = time.Now().Add(-24 * time.Hour)
	case "7d":
		since = time.Now().Add(-7 * 24 * time.Hour)
	case "30d":
		since = time.Now().Add(-30 * 24 * time.Hour)
	default:
		since = time.Now().Add(-24 * time.Hour)
	}

	stats := &models.LogStatsResponse{
		LogsByLevel: make(map[string]int64),
		LogsByTag:   make(map[string]int64),
	}

	// Build base queries with access filtering
	logQuery := s.db.DB.WithContext(ctx).Model(&models.AppLogEntry{})
	sessionQuery := s.db.DB.WithContext(ctx).Model(&models.AppLogSession{})

	if accessParams != nil {
		// Use TableEntries for log queries (no user_id column)
		logQuery = s.applyUserAccessFilterForTable(logQuery, accessParams, TableEntries)
		// Use TableSessions for session queries (has user_id column)
		sessionQuery = s.applyUserAccessFilterForTable(sessionQuery, accessParams, TableSessions)
	}

	// Total logs in period
	logQuery.Where("timestamp >= ?", since).Count(&stats.TotalLogs)

	// Reset query for sessions
	sessionQuery = s.db.DB.WithContext(ctx).Model(&models.AppLogSession{})
	if accessParams != nil {
		sessionQuery = s.applyUserAccessFilter(sessionQuery, accessParams)
	}

	// Total sessions in period
	sessionQuery.Where("started_at >= ?", since).Count(&stats.TotalSessions)

	// Reset for active sessions
	activeQuery := s.db.DB.WithContext(ctx).Model(&models.AppLogSession{})
	if accessParams != nil {
		activeQuery = s.applyUserAccessFilter(activeQuery, accessParams)
	}

	// Active sessions (sessions with activity in last hour)
	activeQuery.Where("started_at >= ?", time.Now().Add(-1*time.Hour)).Count(&stats.ActiveSessions)

	// Logs by level
	type LevelCount struct {
		Level string
		Count int64
	}
	var levelCounts []LevelCount
	levelQuery := s.db.DB.WithContext(ctx).Model(&models.AppLogEntry{})
	if accessParams != nil {
		levelQuery = s.applyUserAccessFilterForTable(levelQuery, accessParams, TableEntries)
	}
	levelQuery.Select("level, COUNT(*) as count").
		Where("timestamp >= ?", since).
		Group("level").
		Find(&levelCounts)

	for _, lc := range levelCounts {
		stats.LogsByLevel[lc.Level] = lc.Count
	}

	// Logs by tag
	type TagCount struct {
		Tag   string
		Count int64
	}
	var tagCounts []TagCount
	tagQuery := s.db.DB.WithContext(ctx).Model(&models.AppLogEntry{})
	if accessParams != nil {
		tagQuery = s.applyUserAccessFilterForTable(tagQuery, accessParams, TableEntries)
	}
	tagQuery.Select("tag, COUNT(*) as count").
		Where("timestamp >= ?", since).
		Group("tag").
		Order("count DESC").
		Limit(10).
		Find(&tagCounts)

	for _, tc := range tagCounts {
		stats.LogsByTag[tc.Tag] = tc.Count
	}

	// Calculate error rate
	if stats.TotalLogs > 0 {
		errorCount := stats.LogsByLevel[models.LogLevelError]
		stats.ErrorRate = float64(errorCount) / float64(stats.TotalLogs) * 100
	}

	// Top errors
	type ErrorMsg struct {
		Message string
		Count   int64
		LastAt  time.Time
	}
	var topErrors []ErrorMsg
	errQuery := s.db.DB.WithContext(ctx).Model(&models.AppLogEntry{})
	if accessParams != nil {
		errQuery = s.applyUserAccessFilterForTable(errQuery, accessParams, TableEntries)
	}
	errQuery.Select("LEFT(message, 200) as message, COUNT(*) as count, MAX(timestamp) as last_at").
		Where("timestamp >= ? AND level = ?", since, models.LogLevelError).
		Group("LEFT(message, 200)").
		Order("count DESC").
		Limit(5).
		Find(&topErrors)

	stats.TopErrors = make([]models.ErrorSummary, 0, len(topErrors))
	for _, e := range topErrors {
		stats.TopErrors = append(stats.TopErrors, models.ErrorSummary{
			Message: e.Message,
			Count:   e.Count,
			LastAt:  e.LastAt.Format(time.RFC3339),
		})
	}

	// Average session duration
	type AvgDuration struct {
		AvgSeconds float64
	}
	var avgDur AvgDuration
	durQuery := s.db.DB.WithContext(ctx).Model(&models.AppLogSession{})
	if accessParams != nil {
		durQuery = s.applyUserAccessFilter(durQuery, accessParams)
	}
	durQuery.Select("AVG(EXTRACT(EPOCH FROM (COALESCE(ended_at, NOW()) - started_at))) as avg_seconds").
		Where("started_at >= ?", since).
		Find(&avgDur)

	if avgDur.AvgSeconds > 0 {
		duration := time.Duration(avgDur.AvgSeconds) * time.Second
		stats.AvgSessionDuration = formatDuration(duration)
	} else {
		stats.AvgSessionDuration = "N/A"
	}

	return stats, nil
}

// ============================================================================
// CLEANUP METHODS
// ============================================================================

// CleanupOldLogs deletes logs older than the specified number of days
func (s *AppLoggingService) CleanupOldLogs(ctx context.Context, retentionDays int) (int64, error) {
	cutoff := time.Now().Add(-time.Duration(retentionDays) * 24 * time.Hour)

	// Delete network requests first (child table)
	result := s.db.DB.WithContext(ctx).
		Where("created_at < ?", cutoff).
		Delete(&models.AppNetworkRequest{})
	if result.Error != nil {
		return 0, fmt.Errorf("failed to delete network requests: %w", result.Error)
	}
	networkDeleted := result.RowsAffected

	// Delete log entries
	result = s.db.DB.WithContext(ctx).
		Where("created_at < ?", cutoff).
		Delete(&models.AppLogEntry{})
	if result.Error != nil {
		return 0, fmt.Errorf("failed to delete log entries: %w", result.Error)
	}
	entriesDeleted := result.RowsAffected

	// Delete batches
	result = s.db.DB.WithContext(ctx).
		Where("created_at < ?", cutoff).
		Delete(&models.AppLogBatch{})
	if result.Error != nil {
		return 0, fmt.Errorf("failed to delete batches: %w", result.Error)
	}

	// Delete empty sessions
	result = s.db.DB.WithContext(ctx).
		Where("started_at < ?", cutoff).
		Where("NOT EXISTS (SELECT 1 FROM app_log_entries e WHERE e.session_id = app_log_sessions.id)").
		Delete(&models.AppLogSession{})
	if result.Error != nil {
		return 0, fmt.Errorf("failed to delete sessions: %w", result.Error)
	}

	total := networkDeleted + entriesDeleted
	s.logger.Info("Cleaned up old logs",
		zap.Int("retention_days", retentionDays),
		zap.Int64("entries_deleted", entriesDeleted),
		zap.Int64("network_deleted", networkDeleted),
	)

	return total, nil
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

func timePtr(t time.Time) *time.Time {
	return &t
}

func formatDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%ds", int(d.Seconds()))
	}
	if d < time.Hour {
		return fmt.Sprintf("%dm %ds", int(d.Minutes()), int(d.Seconds())%60)
	}
	return fmt.Sprintf("%dh %dm", int(d.Hours()), int(d.Minutes())%60)
}

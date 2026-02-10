package handlers

import (
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// DocsHandler handles documentation-related endpoints
type DocsHandler struct {
	db *database.DB
}

// NewDocsHandler creates a new documentation handler
func NewDocsHandler(db *database.DB) *DocsHandler {
	return &DocsHandler{db: db}
}

// CheckDocsAccess verifies user has docs access
// GET /api/docs/access/check
func (h *DocsHandler) CheckDocsAccess(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"error":   "Authentication required",
			"message": "Please login to access documentation features",
		})
		return
	}

	userUUID, err := uuid.Parse(userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid user ID"})
		return
	}

	var access models.DocsAccess
	err = h.db.Where("user_id = ? AND is_active = ?", userUUID, true).
		Preload("User").
		First(&access).Error

	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{
			"success": false,
			"error":   "Documentation access not granted",
			"message": "Please contact an administrator to request access",
		})
		return
	}

	// Check expiration
	if access.ExpiresAt != nil && time.Now().After(*access.ExpiresAt) {
		c.JSON(http.StatusForbidden, gin.H{
			"success": false,
			"error":   "Documentation access has expired",
			"message": "Please contact an administrator to renew access",
		})
		return
	}

	userName := ""
	if access.User != nil {
		userName = access.User.FirstName
		if access.User.LastName != "" {
			userName += " " + access.User.LastName
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"access": gin.H{
			"user_id":     access.UserID,
			"user_name":   userName,
			"role":        access.Role,
			"can_edit":    access.Role == models.DocsRoleEditor,
			"can_comment": true, // Both roles can comment
		},
	})
}

// GetComments retrieves comments for a page
// GET /api/docs/comments?page_id=xxx
func (h *DocsHandler) GetComments(c *gin.Context) {
	pageID := c.Query("page_id")
	if pageID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "page_id required"})
		return
	}

	var comments []models.DocsComment
	err := h.db.Where("page_id = ?", pageID).
		Preload("User").
		Preload("ResolvedBy").
		Order("created_at ASC").
		Find(&comments).Error

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to load comments"})
		return
	}

	// Transform comments for response
	responseComments := make([]gin.H, 0, len(comments))
	for _, comment := range comments {
		userName := "Unknown"
		if comment.User != nil {
			userName = comment.User.FirstName
			if comment.User.LastName != "" {
				userName += " " + comment.User.LastName
			}
		}

		responseComments = append(responseComments, gin.H{
			"id":              comment.ID,
			"page_id":         comment.PageID,
			"page_path":       comment.PagePath,
			"user_id":         comment.UserID,
			"user_name":       userName,
			"content":         comment.Content,
			"selection":       comment.Selection,
			"selection_xpath": comment.SelectionXPath,
			"start_offset":    comment.StartOffset,
			"end_offset":      comment.EndOffset,
			"parent_id":       comment.ParentID,
			"is_resolved":     comment.IsResolved,
			"resolved_at":     comment.ResolvedAt,
			"created_at":      comment.CreatedAt,
			"updated_at":      comment.UpdatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"comments": responseComments,
		"count":    len(comments),
	})
}

// AddComment creates a new comment (requires auth + docs access)
// POST /api/docs/comments
func (h *DocsHandler) AddComment(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Authentication required"})
		return
	}

	userUUID, err := uuid.Parse(userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid user ID"})
		return
	}

	// Verify docs access
	var access models.DocsAccess
	if err := h.db.Where("user_id = ? AND is_active = ?", userUUID, true).First(&access).Error; err != nil {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Documentation access required"})
		return
	}

	// Check expiration
	if access.ExpiresAt != nil && time.Now().After(*access.ExpiresAt) {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Documentation access has expired"})
		return
	}

	var req struct {
		PageID         string `json:"page_id" binding:"required"`
		PagePath       string `json:"page_path"`
		Content        string `json:"content" binding:"required"`
		Selection      string `json:"selection"`
		SelectionXPath string `json:"selection_xpath"`
		StartOffset    int    `json:"start_offset"`
		EndOffset      int    `json:"end_offset"`
		ParentID       string `json:"parent_id"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	comment := models.DocsComment{
		PageID:         req.PageID,
		PagePath:       req.PagePath,
		UserID:         userUUID,
		Content:        req.Content,
		Selection:      req.Selection,
		SelectionXPath: req.SelectionXPath,
		StartOffset:    req.StartOffset,
		EndOffset:      req.EndOffset,
	}

	if req.ParentID != "" {
		parentUUID, err := uuid.Parse(req.ParentID)
		if err == nil {
			comment.ParentID = &parentUUID
		}
	}

	if err := h.db.Create(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to save comment"})
		return
	}

	// Reload with user data
	h.db.Preload("User").First(&comment, comment.ID)

	userName := ""
	if comment.User != nil {
		userName = comment.User.FirstName
		if comment.User.LastName != "" {
			userName += " " + comment.User.LastName
		}
	}

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"comment": gin.H{
			"id":              comment.ID,
			"page_id":         comment.PageID,
			"user_id":         comment.UserID,
			"user_name":       userName,
			"content":         comment.Content,
			"selection":       comment.Selection,
			"selection_xpath": comment.SelectionXPath,
			"created_at":      comment.CreatedAt,
		},
	})
}

// DeleteComment removes a comment
// DELETE /api/docs/comments/:id
func (h *DocsHandler) DeleteComment(c *gin.Context) {
	commentID := c.Param("id")
	userID := c.GetString("user_id")

	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Authentication required"})
		return
	}

	userUUID, _ := uuid.Parse(userID)
	commentUUID, err := uuid.Parse(commentID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid comment ID"})
		return
	}

	// Find the comment
	var comment models.DocsComment
	if err := h.db.First(&comment, commentUUID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Comment not found"})
		return
	}

	// Check if user owns the comment or is an admin
	userRole := c.GetString("role")
	if comment.UserID != userUUID && userRole != models.RoleAdmin && userRole != models.RoleSaasAdmin {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Permission denied"})
		return
	}

	if err := h.db.Delete(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to delete comment"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "Comment deleted"})
}

// ResolveComment marks a comment as resolved
// POST /api/docs/comments/:id/resolve
func (h *DocsHandler) ResolveComment(c *gin.Context) {
	commentID := c.Param("id")
	userID := c.GetString("user_id")

	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Authentication required"})
		return
	}

	userUUID, _ := uuid.Parse(userID)
	commentUUID, err := uuid.Parse(commentID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid comment ID"})
		return
	}

	now := time.Now()
	result := h.db.Model(&models.DocsComment{}).
		Where("id = ?", commentUUID).
		Updates(map[string]interface{}{
			"is_resolved":    true,
			"resolved_at":    now,
			"resolved_by_id": userUUID,
		})

	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to resolve comment"})
		return
	}

	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Comment not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "Comment resolved"})
}

// SaveEdit saves documentation edit (editor role required)
// POST /api/docs/edits
func (h *DocsHandler) SaveEdit(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Authentication required"})
		return
	}

	userUUID, _ := uuid.Parse(userID)

	// Verify editor access
	var access models.DocsAccess
	if err := h.db.Where("user_id = ? AND is_active = ? AND role = ?",
		userUUID, true, models.DocsRoleEditor).First(&access).Error; err != nil {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Editor access required"})
		return
	}

	var req struct {
		PageID     string `json:"page_id" binding:"required"`
		PagePath   string `json:"page_path"`
		FilePath   string `json:"file_path" binding:"required"`
		NewContent string `json:"new_content" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	// Security: Validate file path is within docs directory
	allowedPrefix := "/var/www/liquorpro/docs/docs/"
	if !strings.HasPrefix(req.FilePath, allowedPrefix) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid file path"})
		return
	}

	// Read current content
	oldContent, err := os.ReadFile(req.FilePath)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "File not found"})
		return
	}

	// Create edit record
	edit := models.DocsEdit{
		PageID:     req.PageID,
		PagePath:   req.PagePath,
		UserID:     userUUID,
		FilePath:   req.FilePath,
		OldContent: string(oldContent),
		NewContent: req.NewContent,
		Status:     "approved",
	}

	// Write new content
	if err := os.WriteFile(req.FilePath, []byte(req.NewContent), 0644); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to save edit"})
		return
	}

	h.db.Create(&edit)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"edit_id": edit.ID,
		"message": "Edit saved successfully",
	})
}

// GetEdits retrieves edit history for a page
// GET /api/docs/edits?page_id=xxx
func (h *DocsHandler) GetEdits(c *gin.Context) {
	pageID := c.Query("page_id")

	query := h.db.Model(&models.DocsEdit{}).Preload("User").Order("created_at DESC")
	if pageID != "" {
		query = query.Where("page_id = ?", pageID)
	}

	var edits []models.DocsEdit
	if err := query.Limit(50).Find(&edits).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to load edits"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"edits":   edits,
		"count":   len(edits),
	})
}

// GrantAccess grants docs access to a user (admin only)
// POST /api/docs/admin/access
func (h *DocsHandler) GrantAccess(c *gin.Context) {
	adminRole := c.GetString("role")
	if adminRole != models.RoleAdmin && adminRole != models.RoleSaasAdmin {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Admin access required"})
		return
	}

	adminID := c.GetString("user_id")
	adminUUID, _ := uuid.Parse(adminID)

	var req struct {
		UserID    string `json:"user_id" binding:"required"`
		Role      string `json:"role" binding:"required,oneof=viewer editor"`
		ExpiresAt string `json:"expires_at"` // Optional ISO date
		Notes     string `json:"notes"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	userUUID, err := uuid.Parse(req.UserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid user ID"})
		return
	}

	// Verify user exists
	var user models.User
	if err := h.db.First(&user, userUUID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "User not found"})
		return
	}

	access := models.DocsAccess{
		UserID:      userUUID,
		Role:        models.DocsAccessRole(req.Role),
		GrantedByID: adminUUID,
		IsActive:    true,
		Notes:       req.Notes,
	}

	if req.ExpiresAt != "" {
		exp, err := time.Parse(time.RFC3339, req.ExpiresAt)
		if err == nil {
			access.ExpiresAt = &exp
		}
	}

	// Upsert - update if exists, create if not
	var existing models.DocsAccess
	if err := h.db.Where("user_id = ?", userUUID).First(&existing).Error; err == nil {
		// Update existing
		h.db.Model(&existing).Updates(map[string]interface{}{
			"role":          access.Role,
			"granted_by_id": adminUUID,
			"is_active":     true,
			"notes":         access.Notes,
			"expires_at":    access.ExpiresAt,
		})
		access = existing
	} else {
		// Create new
		h.db.Create(&access)
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"access": gin.H{
			"user_id":   access.UserID,
			"user_name": user.FirstName + " " + user.LastName,
			"role":      access.Role,
			"is_active": access.IsActive,
		},
		"message": "Access granted successfully",
	})
}

// ListAccess lists all users with docs access (admin only)
// GET /api/docs/admin/access
func (h *DocsHandler) ListAccess(c *gin.Context) {
	adminRole := c.GetString("role")
	if adminRole != models.RoleAdmin && adminRole != models.RoleSaasAdmin {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Admin access required"})
		return
	}

	var accessList []models.DocsAccess
	if err := h.db.Preload("User").Preload("GrantedBy").Find(&accessList).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to load access list"})
		return
	}

	response := make([]gin.H, 0, len(accessList))
	for _, access := range accessList {
		userName := ""
		if access.User != nil {
			userName = access.User.FirstName + " " + access.User.LastName
		}
		grantedBy := ""
		if access.GrantedBy != nil {
			grantedBy = access.GrantedBy.FirstName + " " + access.GrantedBy.LastName
		}

		response = append(response, gin.H{
			"id":           access.ID,
			"user_id":      access.UserID,
			"user_name":    userName,
			"user_email":   access.User.Email,
			"role":         access.Role,
			"granted_by":   grantedBy,
			"is_active":    access.IsActive,
			"expires_at":   access.ExpiresAt,
			"notes":        access.Notes,
			"created_at":   access.CreatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"access":  response,
		"count":   len(accessList),
	})
}

// RevokeAccess revokes docs access from a user (admin only)
// DELETE /api/docs/admin/access/:user_id
func (h *DocsHandler) RevokeAccess(c *gin.Context) {
	adminRole := c.GetString("role")
	if adminRole != models.RoleAdmin && adminRole != models.RoleSaasAdmin {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Admin access required"})
		return
	}

	userID := c.Param("user_id")
	userUUID, err := uuid.Parse(userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid user ID"})
		return
	}

	result := h.db.Model(&models.DocsAccess{}).
		Where("user_id = ?", userUUID).
		Update("is_active", false)

	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Access not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Access revoked successfully",
	})
}

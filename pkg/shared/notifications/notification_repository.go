package notifications

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// DeviceToken represents a user's FCM device token
type DeviceToken struct {
	ID          uuid.UUID  `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID      uuid.UUID  `gorm:"type:uuid;not null;index" json:"user_id"`
	TenantID    *uuid.UUID `gorm:"type:uuid;index" json:"tenant_id"`
	Token       string     `gorm:"type:text;not null" json:"token"`
	DeviceType  string     `gorm:"type:varchar(20);default:'android'" json:"device_type"` // android, ios
	DeviceName  string     `gorm:"type:varchar(100)" json:"device_name"`
	IsActive    bool       `gorm:"default:true" json:"is_active"`
	LastUsedAt  time.Time  `gorm:"autoUpdateTime" json:"last_used_at"`
	CreatedAt   time.Time  `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt   time.Time  `gorm:"autoUpdateTime" json:"updated_at"`
}

// TableName returns the table name for DeviceToken
func (DeviceToken) TableName() string {
	return "notification_devices"
}

// NotificationLog represents a sent notification log
type NotificationLog struct {
	ID               uuid.UUID  `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID           uuid.UUID  `gorm:"type:uuid;not null;index" json:"user_id"`
	TenantID         *uuid.UUID `gorm:"type:uuid;index" json:"tenant_id"`
	Type             string     `gorm:"type:varchar(50);not null" json:"type"`
	Title            string     `gorm:"type:varchar(200)" json:"title"`
	Body             string     `gorm:"type:text" json:"body"`
	Data             string     `gorm:"type:jsonb" json:"data"`
	Status           string     `gorm:"type:varchar(20);default:'pending'" json:"status"` // pending, sent, failed
	FailureReason    string     `gorm:"type:text" json:"failure_reason,omitempty"`
	DeviceTokenCount int        `gorm:"default:0" json:"device_token_count"`
	SuccessCount     int        `gorm:"default:0" json:"success_count"`
	FailureCount     int        `gorm:"default:0" json:"failure_count"`
	CreatedAt        time.Time  `gorm:"autoCreateTime" json:"created_at"`
}

// TableName returns the table name for NotificationLog
func (NotificationLog) TableName() string {
	return "notification_logs"
}

// NotificationRepository handles database operations for notifications
type NotificationRepository struct {
	db *gorm.DB
}

// NewNotificationRepository creates a new notification repository
func NewNotificationRepository(db *gorm.DB) *NotificationRepository {
	return &NotificationRepository{db: db}
}

// RegisterDeviceToken registers or updates a device token for a user
func (r *NotificationRepository) RegisterDeviceToken(ctx context.Context, userID, tenantID uuid.UUID, token, deviceType, deviceName string) error {
	// Check if token already exists for this user
	var existing DeviceToken
	err := r.db.WithContext(ctx).
		Where("user_id = ? AND token = ?", userID, token).
		First(&existing).Error

	if err == nil {
		// Token exists, update it
		existing.IsActive = true
		existing.DeviceType = deviceType
		existing.DeviceName = deviceName
		existing.LastUsedAt = time.Now()
		if tenantID != uuid.Nil {
			existing.TenantID = &tenantID
		}
		return r.db.WithContext(ctx).Save(&existing).Error
	}

	if err != gorm.ErrRecordNotFound {
		return fmt.Errorf("failed to check existing token: %w", err)
	}

	// Create new token
	deviceToken := DeviceToken{
		UserID:     userID,
		Token:      token,
		DeviceType: deviceType,
		DeviceName: deviceName,
		IsActive:   true,
		LastUsedAt: time.Now(),
	}
	if tenantID != uuid.Nil {
		deviceToken.TenantID = &tenantID
	}

	return r.db.WithContext(ctx).Create(&deviceToken).Error
}

// GetActiveTokensForUser returns all active device tokens for a user
func (r *NotificationRepository) GetActiveTokensForUser(ctx context.Context, userID uuid.UUID) ([]string, error) {
	var tokens []DeviceToken
	err := r.db.WithContext(ctx).
		Where("user_id = ? AND is_active = ?", userID, true).
		Find(&tokens).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get device tokens: %w", err)
	}

	result := make([]string, 0, len(tokens))
	for _, t := range tokens {
		result = append(result, t.Token)
	}

	return result, nil
}

// GetActiveTokensForUsers returns all active device tokens for multiple users
func (r *NotificationRepository) GetActiveTokensForUsers(ctx context.Context, userIDs []uuid.UUID) (map[uuid.UUID][]string, error) {
	var tokens []DeviceToken
	err := r.db.WithContext(ctx).
		Where("user_id IN ? AND is_active = ?", userIDs, true).
		Find(&tokens).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get device tokens: %w", err)
	}

	result := make(map[uuid.UUID][]string)
	for _, t := range tokens {
		result[t.UserID] = append(result[t.UserID], t.Token)
	}

	return result, nil
}

// DeactivateToken deactivates a device token
func (r *NotificationRepository) DeactivateToken(ctx context.Context, token string) error {
	return r.db.WithContext(ctx).
		Model(&DeviceToken{}).
		Where("token = ?", token).
		Update("is_active", false).Error
}

// LogNotification logs a sent notification
func (r *NotificationRepository) LogNotification(ctx context.Context, log *NotificationLog) error {
	return r.db.WithContext(ctx).Create(log).Error
}

// GetNotificationsForUser returns recent notifications for a user
func (r *NotificationRepository) GetNotificationsForUser(ctx context.Context, userID uuid.UUID, limit int) ([]NotificationLog, error) {
	var logs []NotificationLog
	err := r.db.WithContext(ctx).
		Where("user_id = ?", userID).
		Order("created_at DESC").
		Limit(limit).
		Find(&logs).Error

	return logs, err
}

// CleanupOldTokens removes inactive tokens older than specified days
func (r *NotificationRepository) CleanupOldTokens(ctx context.Context, daysOld int) (int64, error) {
	cutoff := time.Now().AddDate(0, 0, -daysOld)
	result := r.db.WithContext(ctx).
		Where("is_active = ? AND last_used_at < ?", false, cutoff).
		Delete(&DeviceToken{})

	return result.RowsAffected, result.Error
}

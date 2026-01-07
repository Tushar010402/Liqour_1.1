package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/alarms/handlers"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// SetupRoutes configures all alarm service routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, alarmHandler *handlers.AlarmHandler) {
	// All routes require authentication and tenant isolation
	api := router.Group("/api/alarms")
	api.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	api.Use(middleware.TenantMiddleware())

	// Alarm Definition Routes (read-only for most users)
	definitions := api.Group("/definitions")
	{
		definitions.GET("", alarmHandler.GetAlarmDefinitions)
		definitions.GET("/:code", alarmHandler.GetAlarmDefinition)
	}

	// Alarm Configuration Routes (admin/owner only for modifications)
	configurations := api.Group("/configurations")
	{
		configurations.GET("", alarmHandler.GetAlarmConfigurations)
		configurations.GET("/:code", alarmHandler.GetAlarmConfiguration)
		configurations.PUT("", middleware.RoleMiddleware("admin", "owner"), alarmHandler.UpdateAlarmConfiguration)
	}

	// Alarm Instance Routes
	{
		// Get alarms with filters
		api.GET("", alarmHandler.GetAlarms)

		// Get single alarm with history and notes
		api.GET("/:id", alarmHandler.GetAlarm)

		// Alarm actions
		api.POST("/:id/acknowledge", alarmHandler.AcknowledgeAlarm)
		api.POST("/:id/resolve", alarmHandler.ResolveAlarm)
		api.POST("/:id/snooze", alarmHandler.SnoozeAlarm)
		api.POST("/:id/notes", alarmHandler.AddAlarmNote)
	}

	// Alarm Counts and Stats
	{
		api.GET("/counts", alarmHandler.GetAlarmCounts)
		api.GET("/stats", alarmHandler.GetAlarmStats)
	}

	// User Subscription Routes
	subscriptions := api.Group("/subscriptions")
	{
		subscriptions.GET("", alarmHandler.GetUserSubscriptions)
		subscriptions.PUT("", alarmHandler.UpdateUserSubscription)
	}

	// Bulk Actions
	bulk := api.Group("/bulk")
	{
		bulk.POST("/acknowledge", alarmHandler.BulkAcknowledge)
		bulk.POST("/resolve", alarmHandler.BulkResolve)
	}

	// Admin Routes
	admin := api.Group("/admin")
	admin.Use(middleware.RoleMiddleware("admin", "owner"))
	{
		admin.POST("/trigger", alarmHandler.TriggerAlarm)
		admin.POST("/run-checks", alarmHandler.RunAlarmChecks)
	}
}

// SetupGatewayRoutes sets up alarm routes through the gateway
func SetupGatewayRoutes(router *gin.RouterGroup, alarmHandler *handlers.AlarmHandler) {
	alarms := router.Group("/alarms")
	{
		// Alarm Definition Routes
		alarms.GET("/definitions", alarmHandler.GetAlarmDefinitions)
		alarms.GET("/definitions/:code", alarmHandler.GetAlarmDefinition)

		// Alarm Configuration Routes
		alarms.GET("/configurations", alarmHandler.GetAlarmConfigurations)
		alarms.GET("/configurations/:code", alarmHandler.GetAlarmConfiguration)
		alarms.PUT("/configurations", middleware.RoleMiddleware("admin", "owner"), alarmHandler.UpdateAlarmConfiguration)

		// Alarm Instance Routes
		alarms.GET("", alarmHandler.GetAlarms)
		alarms.GET("/:id", alarmHandler.GetAlarm)
		alarms.POST("/:id/acknowledge", alarmHandler.AcknowledgeAlarm)
		alarms.POST("/:id/resolve", alarmHandler.ResolveAlarm)
		alarms.POST("/:id/snooze", alarmHandler.SnoozeAlarm)
		alarms.POST("/:id/notes", alarmHandler.AddAlarmNote)

		// Counts and Stats
		alarms.GET("/counts", alarmHandler.GetAlarmCounts)
		alarms.GET("/stats", alarmHandler.GetAlarmStats)

		// User Subscriptions
		alarms.GET("/subscriptions", alarmHandler.GetUserSubscriptions)
		alarms.PUT("/subscriptions", alarmHandler.UpdateUserSubscription)

		// Bulk Actions
		alarms.POST("/bulk/acknowledge", alarmHandler.BulkAcknowledge)
		alarms.POST("/bulk/resolve", alarmHandler.BulkResolve)

		// Admin Routes
		alarms.POST("/admin/trigger", middleware.RoleMiddleware("admin", "owner"), alarmHandler.TriggerAlarm)
		alarms.POST("/admin/run-checks", middleware.RoleMiddleware("admin", "owner"), alarmHandler.RunAlarmChecks)
	}
}

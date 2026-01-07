package services

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// WorkflowNotificationService handles business workflow notifications
// This service sends notifications for approval workflows:
// - Sale approvals/rejections
// - Purchase order approvals/rejections
// - Daily sales record approvals/rejections
type WorkflowNotificationService struct {
	notificationService *NotificationService
	db                  *database.DB
}

// NewWorkflowNotificationService creates a new workflow notification service
func NewWorkflowNotificationService(db *database.DB, notificationService *NotificationService) *WorkflowNotificationService {
	return &WorkflowNotificationService{
		db:                  db,
		notificationService: notificationService,
	}
}

// ApproverRoles defines roles that can approve requests
var ApproverRoles = []string{"manager", "assistant_manager", "admin", "owner"}

// =============================================================================
// SALE WORKFLOW NOTIFICATIONS
// =============================================================================

// NotifySaleCreated notifies approvers when a new sale is created
func (w *WorkflowNotificationService) NotifySaleCreated(ctx context.Context, sale *models.Sale) error {
	if sale == nil || sale.TenantID == nil {
		return fmt.Errorf("invalid sale data")
	}

	// Get creator info
	var creator models.User
	if err := w.db.First(&creator, "id = ?", sale.CreatedByID).Error; err != nil {
		log.Printf("[WORKFLOW] Failed to get sale creator: %v", err)
		return err
	}

	// Get shop info
	var shop models.Shop
	if err := w.db.First(&shop, "id = ?", sale.ShopID).Error; err != nil {
		log.Printf("[WORKFLOW] Failed to get shop: %v", err)
		return err
	}

	// Get approvers for this tenant
	approvers, err := w.GetApprovers(ctx, *sale.TenantID, &sale.ShopID)
	if err != nil {
		log.Printf("[WORKFLOW] Failed to get approvers: %v", err)
		return err
	}

	if len(approvers) == 0 {
		log.Printf("[WORKFLOW] No approvers found for tenant %s", sale.TenantID)
		return nil
	}

	// Build modern notification content
	title := fmt.Sprintf("🔔 Approve Sale • %s", shop.Name)
	body := fmt.Sprintf("₹%.0f from %s • Tap to review",
		sale.TotalAmount,
		creator.FullName(),
	)

	// Send to all approvers
	for _, approver := range approvers {
		// Don't notify the creator if they're also an approver
		if approver.ID == sale.CreatedByID {
			continue
		}

		req := &models.SendNotificationRequest{
			UserID:   approver.ID,
			Category: models.NotificationCategoryApproval,
			Priority: models.NotificationPriorityHigh,
			Title:    title,
			Body:     body,
			Data: map[string]interface{}{
				"action":        "open_sale_approval",
				"sale_id":       sale.ID.String(),
				"sale_number":   sale.SaleNumber,
				"amount":        sale.TotalAmount,
				"shop_id":       sale.ShopID.String(),
				"shop_name":     shop.Name,
				"created_by":    creator.FullName(),
				"created_by_id": sale.CreatedByID.String(),
				"created_at":    sale.CreatedAt.Format(time.RFC3339),
			},
			ActionURL: fmt.Sprintf("/sales/%s/approve", sale.ID),
			Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
			// Modern notification features
			Actions: []models.NotificationAction{
				{Action: "approve", Label: "Approve", Icon: "ic_check", Style: "primary", URL: fmt.Sprintf("/sales/%s/approve", sale.ID)},
				{Action: "reject", Label: "Reject", Icon: "ic_close", Style: "destructive", URL: fmt.Sprintf("/sales/%s/reject", sale.ID)},
			},
			ThreadID:    fmt.Sprintf("shop_%s_approvals", sale.ShopID),
			ChannelID:   "approvals",
			CollapseKey: fmt.Sprintf("sale_approval_%s", sale.ID),
		}

		if _, err := w.notificationService.SendNotification(ctx, *sale.TenantID, approver.ID, req); err != nil {
			log.Printf("[WORKFLOW] Failed to notify approver %s for sale %s: %v", approver.ID, sale.ID, err)
		} else {
			log.Printf("[WORKFLOW] Notified approver %s for new sale %s", approver.ID, sale.SaleNumber)
		}
	}

	return nil
}

// NotifySaleApproved notifies the creator when their sale is approved
func (w *WorkflowNotificationService) NotifySaleApproved(ctx context.Context, sale *models.Sale, approver *models.User) error {
	if sale == nil || sale.TenantID == nil || approver == nil {
		return fmt.Errorf("invalid sale or approver data")
	}

	// Modern, concise notification
	title := "✅ Sale Approved"
	body := fmt.Sprintf("₹%.0f approved by %s",
		sale.TotalAmount,
		approver.FullName(),
	)

	req := &models.SendNotificationRequest{
		UserID:   sale.CreatedByID,
		Category: models.NotificationCategorySales,
		Priority: models.NotificationPriorityNormal,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":         "open_sale_details",
			"sale_id":        sale.ID.String(),
			"sale_number":    sale.SaleNumber,
			"amount":         sale.TotalAmount,
			"status":         "approved",
			"approved_by":    approver.FullName(),
			"approved_by_id": approver.ID.String(),
			"approved_at":    time.Now().Format(time.RFC3339),
		},
		ActionURL: fmt.Sprintf("/sales/%s", sale.ID),
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
		// Modern notification features
		ThreadID:  fmt.Sprintf("shop_%s_sales", sale.ShopID),
		ChannelID: "sales",
	}

	if _, err := w.notificationService.SendNotification(ctx, *sale.TenantID, sale.CreatedByID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify creator %s for approved sale %s: %v", sale.CreatedByID, sale.ID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified creator %s that sale %s was approved by %s", sale.CreatedByID, sale.SaleNumber, approver.FullName())
	return nil
}

// NotifySaleRejected notifies the creator when their sale is rejected
func (w *WorkflowNotificationService) NotifySaleRejected(ctx context.Context, sale *models.Sale, rejector *models.User, reason string) error {
	if sale == nil || sale.TenantID == nil || rejector == nil {
		return fmt.Errorf("invalid sale or rejector data")
	}

	// Modern, action-oriented notification
	title := "⚠️ Sale Needs Edit"
	body := fmt.Sprintf("%s • Tap to fix", reason)

	req := &models.SendNotificationRequest{
		UserID:   sale.CreatedByID,
		Category: models.NotificationCategorySales,
		Priority: models.NotificationPriorityHigh,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":           "open_sale_edit",
			"sale_id":          sale.ID.String(),
			"sale_number":      sale.SaleNumber,
			"amount":           sale.TotalAmount,
			"status":           "rejected",
			"rejected_by":      rejector.FullName(),
			"rejected_by_id":   rejector.ID.String(),
			"rejection_reason": reason,
			"rejected_at":      time.Now().Format(time.RFC3339),
		},
		ActionURL: fmt.Sprintf("/sales/%s/edit", sale.ID),
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
		// Modern notification features
		Actions: []models.NotificationAction{
			{Action: "edit", Label: "Edit Sale", Icon: "ic_edit", Style: "primary", URL: fmt.Sprintf("/sales/%s/edit", sale.ID)},
		},
		ThreadID:  fmt.Sprintf("shop_%s_sales", sale.ShopID),
		ChannelID: "sales",
	}

	if _, err := w.notificationService.SendNotification(ctx, *sale.TenantID, sale.CreatedByID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify creator %s for rejected sale %s: %v", sale.CreatedByID, sale.ID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified creator %s that sale %s was rejected by %s: %s", sale.CreatedByID, sale.SaleNumber, rejector.FullName(), reason)
	return nil
}

// =============================================================================
// DAILY SALES RECORD WORKFLOW NOTIFICATIONS
// =============================================================================

// NotifyDailySalesCreated notifies approvers when a new daily sales record is created
func (w *WorkflowNotificationService) NotifyDailySalesCreated(ctx context.Context, record *models.DailySalesRecord) error {
	if record == nil || record.TenantID == nil {
		return fmt.Errorf("invalid daily sales record data")
	}

	// Get creator info
	var creator models.User
	if err := w.db.First(&creator, "id = ?", record.CreatedByID).Error; err != nil {
		log.Printf("[WORKFLOW] Failed to get daily sales creator: %v", err)
		return err
	}

	// Get shop info
	var shop models.Shop
	if err := w.db.First(&shop, "id = ?", record.ShopID).Error; err != nil {
		log.Printf("[WORKFLOW] Failed to get shop: %v", err)
		return err
	}

	// Get approvers for this tenant
	approvers, err := w.GetApprovers(ctx, *record.TenantID, &record.ShopID)
	if err != nil {
		log.Printf("[WORKFLOW] Failed to get approvers: %v", err)
		return err
	}

	if len(approvers) == 0 {
		log.Printf("[WORKFLOW] No approvers found for tenant %s", record.TenantID)
		return nil
	}

	// Build modern notification content
	recordDate := record.RecordDate.Format("02 Jan")
	title := fmt.Sprintf("📊 Daily Sales • %s", shop.Name)
	body := fmt.Sprintf("₹%.0f (%s) awaits approval",
		record.TotalSalesAmount,
		recordDate,
	)

	// Send to all approvers
	for _, approver := range approvers {
		// Don't notify the creator if they're also an approver
		if approver.ID == record.CreatedByID {
			continue
		}

		req := &models.SendNotificationRequest{
			UserID:   approver.ID,
			Category: models.NotificationCategoryApproval,
			Priority: models.NotificationPriorityHigh,
			Title:    title,
			Body:     body,
			Data: map[string]interface{}{
				"action":        "open_daily_sales_approval",
				"record_id":     record.ID.String(),
				"record_date":   recordDate,
				"amount":        record.TotalSalesAmount,
				"shop_id":       record.ShopID.String(),
				"shop_name":     shop.Name,
				"created_by":    creator.FullName(),
				"created_by_id": record.CreatedByID.String(),
				"cash_amount":   record.TotalCashAmount,
				"card_amount":   record.TotalCardAmount,
				"upi_amount":    record.TotalUpiAmount,
				"credit_amount": record.TotalCreditAmount,
			},
			ActionURL: fmt.Sprintf("/daily-sales/%s/approve", record.ID),
			Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
			// Modern notification features
			Actions: []models.NotificationAction{
				{Action: "approve", Label: "Approve", Icon: "ic_check", Style: "primary", URL: fmt.Sprintf("/daily-sales/%s/approve", record.ID)},
				{Action: "view", Label: "View Details", Icon: "ic_view", Style: "default", URL: fmt.Sprintf("/daily-sales/%s", record.ID)},
			},
			ThreadID:    fmt.Sprintf("shop_%s_approvals", record.ShopID),
			ChannelID:   "approvals",
			CollapseKey: fmt.Sprintf("daily_sales_approval_%s", record.ID),
		}

		if _, err := w.notificationService.SendNotification(ctx, *record.TenantID, approver.ID, req); err != nil {
			log.Printf("[WORKFLOW] Failed to notify approver %s for daily sales %s: %v", approver.ID, record.ID, err)
		} else {
			log.Printf("[WORKFLOW] Notified approver %s for new daily sales record %s", approver.ID, record.ID)
		}
	}

	return nil
}

// NotifyDailySalesApproved notifies the creator when their daily sales record is approved
func (w *WorkflowNotificationService) NotifyDailySalesApproved(ctx context.Context, record *models.DailySalesRecord, approver *models.User) error {
	if record == nil || record.TenantID == nil || approver == nil {
		return fmt.Errorf("invalid record or approver data")
	}

	// Modern, concise notification
	recordDate := record.RecordDate.Format("02 Jan")
	title := "✅ Sales Approved"
	body := fmt.Sprintf("₹%.0f verified • Cash credited", record.TotalSalesAmount)

	req := &models.SendNotificationRequest{
		UserID:   record.CreatedByID,
		Category: models.NotificationCategorySales,
		Priority: models.NotificationPriorityNormal,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":         "open_daily_sales_details",
			"record_id":      record.ID.String(),
			"record_date":    recordDate,
			"amount":         record.TotalSalesAmount,
			"status":         "approved",
			"approved_by":    approver.FullName(),
			"approved_by_id": approver.ID.String(),
			"approved_at":    time.Now().Format(time.RFC3339),
		},
		ActionURL: fmt.Sprintf("/daily-sales/%s", record.ID),
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
		// Modern notification features
		ThreadID:  fmt.Sprintf("shop_%s_sales", record.ShopID),
		ChannelID: "sales",
	}

	if _, err := w.notificationService.SendNotification(ctx, *record.TenantID, record.CreatedByID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify creator %s for approved daily sales %s: %v", record.CreatedByID, record.ID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified creator %s that daily sales %s was approved by %s", record.CreatedByID, record.ID, approver.FullName())
	return nil
}

// NotifyDailySalesRejected notifies the creator when their daily sales record is rejected
func (w *WorkflowNotificationService) NotifyDailySalesRejected(ctx context.Context, record *models.DailySalesRecord, rejector *models.User, reason string) error {
	if record == nil || record.TenantID == nil || rejector == nil {
		return fmt.Errorf("invalid record or rejector data")
	}

	// Modern, action-oriented notification
	recordDate := record.RecordDate.Format("02 Jan")
	title := "⚠️ Sales Record Issue"
	body := fmt.Sprintf("%s • Tap to correct", reason)

	req := &models.SendNotificationRequest{
		UserID:   record.CreatedByID,
		Category: models.NotificationCategorySales,
		Priority: models.NotificationPriorityHigh,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":           "open_daily_sales_edit",
			"record_id":        record.ID.String(),
			"record_date":      recordDate,
			"amount":           record.TotalSalesAmount,
			"status":           "rejected",
			"rejected_by":      rejector.FullName(),
			"rejected_by_id":   rejector.ID.String(),
			"rejection_reason": reason,
			"rejected_at":      time.Now().Format(time.RFC3339),
		},
		ActionURL: fmt.Sprintf("/daily-sales/%s/edit", record.ID),
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
		// Modern notification features
		Actions: []models.NotificationAction{
			{Action: "edit", Label: "Edit Record", Icon: "ic_edit", Style: "primary", URL: fmt.Sprintf("/daily-sales/%s/edit", record.ID)},
		},
		ThreadID:  fmt.Sprintf("shop_%s_sales", record.ShopID),
		ChannelID: "sales",
	}

	if _, err := w.notificationService.SendNotification(ctx, *record.TenantID, record.CreatedByID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify creator %s for rejected daily sales %s: %v", record.CreatedByID, record.ID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified creator %s that daily sales %s was rejected by %s: %s", record.CreatedByID, record.ID, rejector.FullName(), reason)
	return nil
}

// =============================================================================
// PURCHASE WORKFLOW NOTIFICATIONS
// =============================================================================

// NotifyPurchaseCreated notifies approvers when a new purchase order is created
func (w *WorkflowNotificationService) NotifyPurchaseCreated(ctx context.Context, purchase *models.StockPurchase) error {
	if purchase == nil || purchase.TenantID == nil {
		return fmt.Errorf("invalid purchase data")
	}

	// Get creator info
	var creator models.User
	if err := w.db.First(&creator, "id = ?", purchase.CreatedBy).Error; err != nil {
		log.Printf("[WORKFLOW] Failed to get purchase creator: %v", err)
		return err
	}

	// Get vendor info
	var vendor models.Vendor
	if err := w.db.First(&vendor, "id = ?", purchase.VendorID).Error; err != nil {
		log.Printf("[WORKFLOW] Failed to get vendor: %v", err)
		return err
	}

	// Get shop info
	var shop models.Shop
	if err := w.db.First(&shop, "id = ?", purchase.ShopID).Error; err != nil {
		log.Printf("[WORKFLOW] Failed to get shop: %v", err)
		return err
	}

	// Get approvers for this tenant
	approvers, err := w.GetApprovers(ctx, *purchase.TenantID, &purchase.ShopID)
	if err != nil {
		log.Printf("[WORKFLOW] Failed to get approvers: %v", err)
		return err
	}

	if len(approvers) == 0 {
		log.Printf("[WORKFLOW] No approvers found for tenant %s", purchase.TenantID)
		return nil
	}

	// Build modern notification content
	title := fmt.Sprintf("📦 New PO • %s", shop.Name)
	body := fmt.Sprintf("₹%.0f from %s • Review now",
		purchase.TotalAmount,
		vendor.Name,
	)

	// Send to all approvers
	for _, approver := range approvers {
		// Don't notify the creator if they're also an approver
		if approver.ID == purchase.CreatedBy {
			continue
		}

		req := &models.SendNotificationRequest{
			UserID:   approver.ID,
			Category: models.NotificationCategoryApproval,
			Priority: models.NotificationPriorityHigh,
			Title:    title,
			Body:     body,
			Data: map[string]interface{}{
				"action":          "open_purchase_approval",
				"purchase_id":     purchase.ID.String(),
				"purchase_number": purchase.PurchaseNumber,
				"amount":          purchase.TotalAmount,
				"vendor_id":       purchase.VendorID.String(),
				"vendor_name":     vendor.Name,
				"shop_id":         purchase.ShopID.String(),
				"shop_name":       shop.Name,
				"created_by":      creator.FullName(),
				"created_by_id":   purchase.CreatedBy.String(),
			},
			ActionURL: fmt.Sprintf("/purchases/%s/approve", purchase.ID),
			Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
			// Modern notification features
			Actions: []models.NotificationAction{
				{Action: "approve", Label: "Approve", Icon: "ic_check", Style: "primary", URL: fmt.Sprintf("/purchases/%s/approve", purchase.ID)},
				{Action: "reject", Label: "Reject", Icon: "ic_close", Style: "destructive", URL: fmt.Sprintf("/purchases/%s/reject", purchase.ID)},
				{Action: "view", Label: "View", Icon: "ic_view", Style: "default", URL: fmt.Sprintf("/purchases/%s", purchase.ID)},
			},
			ThreadID:    fmt.Sprintf("shop_%s_approvals", purchase.ShopID),
			ChannelID:   "approvals",
			CollapseKey: fmt.Sprintf("purchase_approval_%s", purchase.ID),
		}

		if _, err := w.notificationService.SendNotification(ctx, *purchase.TenantID, approver.ID, req); err != nil {
			log.Printf("[WORKFLOW] Failed to notify approver %s for purchase %s: %v", approver.ID, purchase.ID, err)
		} else {
			log.Printf("[WORKFLOW] Notified approver %s for new purchase %s", approver.ID, purchase.PurchaseNumber)
		}
	}

	return nil
}

// NotifyPurchaseApproved notifies the creator when their purchase order is approved
func (w *WorkflowNotificationService) NotifyPurchaseApproved(ctx context.Context, purchase *models.StockPurchase, approver *models.User) error {
	if purchase == nil || purchase.TenantID == nil || approver == nil {
		return fmt.Errorf("invalid purchase or approver data")
	}

	// Get vendor name for modern notification
	var vendor models.Vendor
	vendorName := "vendor"
	if err := w.db.First(&vendor, "id = ?", purchase.VendorID).Error; err == nil {
		vendorName = vendor.Name
	}

	// Modern, concise notification
	title := "✅ PO Approved"
	body := fmt.Sprintf("%s order confirmed", vendorName)

	req := &models.SendNotificationRequest{
		UserID:   purchase.CreatedBy,
		Category: models.NotificationCategoryInventory,
		Priority: models.NotificationPriorityNormal,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":          "open_purchase_details",
			"purchase_id":     purchase.ID.String(),
			"purchase_number": purchase.PurchaseNumber,
			"amount":          purchase.TotalAmount,
			"status":          "approved",
			"approved_by":     approver.FullName(),
			"approved_by_id":  approver.ID.String(),
			"approved_at":     time.Now().Format(time.RFC3339),
		},
		ActionURL: fmt.Sprintf("/purchases/%s", purchase.ID),
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
		// Modern notification features
		ThreadID:  fmt.Sprintf("shop_%s_inventory", purchase.ShopID),
		ChannelID: "inventory",
	}

	if _, err := w.notificationService.SendNotification(ctx, *purchase.TenantID, purchase.CreatedBy, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify creator %s for approved purchase %s: %v", purchase.CreatedBy, purchase.ID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified creator %s that purchase %s was approved by %s", purchase.CreatedBy, purchase.PurchaseNumber, approver.FullName())
	return nil
}

// NotifyPurchaseRejected notifies the creator when their purchase order is rejected
func (w *WorkflowNotificationService) NotifyPurchaseRejected(ctx context.Context, purchase *models.StockPurchase, rejector *models.User, reason string) error {
	if purchase == nil || purchase.TenantID == nil || rejector == nil {
		return fmt.Errorf("invalid purchase or rejector data")
	}

	// Modern, action-oriented notification
	title := "⚠️ PO Rejected"
	body := fmt.Sprintf("%s • Tap to revise", reason)

	req := &models.SendNotificationRequest{
		UserID:   purchase.CreatedBy,
		Category: models.NotificationCategoryInventory,
		Priority: models.NotificationPriorityHigh,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":           "open_purchase_edit",
			"purchase_id":      purchase.ID.String(),
			"purchase_number":  purchase.PurchaseNumber,
			"amount":           purchase.TotalAmount,
			"status":           "rejected",
			"rejected_by":      rejector.FullName(),
			"rejected_by_id":   rejector.ID.String(),
			"rejection_reason": reason,
			"rejected_at":      time.Now().Format(time.RFC3339),
		},
		ActionURL: fmt.Sprintf("/purchases/%s/edit", purchase.ID),
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
		// Modern notification features
		Actions: []models.NotificationAction{
			{Action: "edit", Label: "Edit PO", Icon: "ic_edit", Style: "primary", URL: fmt.Sprintf("/purchases/%s/edit", purchase.ID)},
		},
		ThreadID:  fmt.Sprintf("shop_%s_inventory", purchase.ShopID),
		ChannelID: "inventory",
	}

	if _, err := w.notificationService.SendNotification(ctx, *purchase.TenantID, purchase.CreatedBy, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify creator %s for rejected purchase %s: %v", purchase.CreatedBy, purchase.ID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified creator %s that purchase %s was rejected by %s: %s", purchase.CreatedBy, purchase.PurchaseNumber, rejector.FullName(), reason)
	return nil
}

// =============================================================================
// SALE RETURN WORKFLOW NOTIFICATIONS
// =============================================================================

// NotifySaleReturnCreated notifies approvers when a new sale return is created
func (w *WorkflowNotificationService) NotifySaleReturnCreated(ctx context.Context, saleReturn *models.SaleReturn) error {
	if saleReturn == nil || saleReturn.TenantID == nil {
		return fmt.Errorf("invalid sale return data")
	}

	// Get creator info
	var creator models.User
	if err := w.db.First(&creator, "id = ?", saleReturn.CreatedByID).Error; err != nil {
		log.Printf("[WORKFLOW] Failed to get sale return creator: %v", err)
		return err
	}

	// Get original sale info
	var sale models.Sale
	if err := w.db.First(&sale, "id = ?", saleReturn.SaleID).Error; err != nil {
		log.Printf("[WORKFLOW] Failed to get original sale: %v", err)
		return err
	}

	// Get approvers for this tenant
	approvers, err := w.GetApprovers(ctx, *saleReturn.TenantID, &sale.ShopID)
	if err != nil {
		log.Printf("[WORKFLOW] Failed to get approvers: %v", err)
		return err
	}

	if len(approvers) == 0 {
		log.Printf("[WORKFLOW] No approvers found for tenant %s", saleReturn.TenantID)
		return nil
	}

	// Get shop info for modern notification
	var shop models.Shop
	shopName := "Shop"
	if err := w.db.First(&shop, "id = ?", sale.ShopID).Error; err == nil {
		shopName = shop.Name
	}

	// Build modern notification content
	title := fmt.Sprintf("🔄 Return Request • %s", shopName)
	body := fmt.Sprintf("₹%.0f from %s • Tap to review",
		saleReturn.ReturnAmount,
		creator.FullName(),
	)

	// Send to all approvers
	for _, approver := range approvers {
		// Don't notify the creator if they're also an approver
		if approver.ID == saleReturn.CreatedByID {
			continue
		}

		req := &models.SendNotificationRequest{
			UserID:   approver.ID,
			Category: models.NotificationCategoryApproval,
			Priority: models.NotificationPriorityHigh,
			Title:    title,
			Body:     body,
			Data: map[string]interface{}{
				"action":        "open_sale_return_approval",
				"return_id":     saleReturn.ID.String(),
				"return_number": saleReturn.ReturnNumber,
				"sale_id":       sale.ID.String(),
				"sale_number":   sale.SaleNumber,
				"amount":        saleReturn.ReturnAmount,
				"reason":        saleReturn.Reason,
				"created_by":    creator.FullName(),
				"created_by_id": saleReturn.CreatedByID.String(),
			},
			ActionURL: fmt.Sprintf("/sale-returns/%s/approve", saleReturn.ID),
			Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
			// Modern notification features
			Actions: []models.NotificationAction{
				{Action: "approve", Label: "Approve", Icon: "ic_check", Style: "primary", URL: fmt.Sprintf("/sale-returns/%s/approve", saleReturn.ID)},
				{Action: "reject", Label: "Reject", Icon: "ic_close", Style: "destructive", URL: fmt.Sprintf("/sale-returns/%s/reject", saleReturn.ID)},
			},
			ThreadID:    fmt.Sprintf("shop_%s_approvals", sale.ShopID),
			ChannelID:   "approvals",
			CollapseKey: fmt.Sprintf("sale_return_approval_%s", saleReturn.ID),
		}

		if _, err := w.notificationService.SendNotification(ctx, *saleReturn.TenantID, approver.ID, req); err != nil {
			log.Printf("[WORKFLOW] Failed to notify approver %s for sale return %s: %v", approver.ID, saleReturn.ID, err)
		} else {
			log.Printf("[WORKFLOW] Notified approver %s for new sale return %s", approver.ID, saleReturn.ReturnNumber)
		}
	}

	return nil
}

// NotifySaleReturnApproved notifies the creator when their sale return is approved
func (w *WorkflowNotificationService) NotifySaleReturnApproved(ctx context.Context, saleReturn *models.SaleReturn, approver *models.User) error {
	if saleReturn == nil || saleReturn.TenantID == nil || approver == nil {
		return fmt.Errorf("invalid sale return or approver data")
	}

	// Get sale info for shop ID
	var sale models.Sale
	if err := w.db.First(&sale, "id = ?", saleReturn.SaleID).Error; err != nil {
		log.Printf("[WORKFLOW] Failed to get original sale for return: %v", err)
	}

	// Modern, concise notification
	title := "✅ Return Approved"
	body := fmt.Sprintf("₹%.0f refund processed • Stock restored", saleReturn.ReturnAmount)

	req := &models.SendNotificationRequest{
		UserID:   saleReturn.CreatedByID,
		Category: models.NotificationCategorySales,
		Priority: models.NotificationPriorityNormal,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":         "open_sale_return_details",
			"return_id":      saleReturn.ID.String(),
			"return_number":  saleReturn.ReturnNumber,
			"amount":         saleReturn.ReturnAmount,
			"status":         "approved",
			"approved_by":    approver.FullName(),
			"approved_by_id": approver.ID.String(),
			"approved_at":    time.Now().Format(time.RFC3339),
		},
		ActionURL: fmt.Sprintf("/sale-returns/%s", saleReturn.ID),
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
		// Modern notification features
		ThreadID:  fmt.Sprintf("shop_%s_sales", sale.ShopID),
		ChannelID: "sales",
	}

	if _, err := w.notificationService.SendNotification(ctx, *saleReturn.TenantID, saleReturn.CreatedByID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify creator %s for approved sale return %s: %v", saleReturn.CreatedByID, saleReturn.ID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified creator %s that sale return %s was approved by %s", saleReturn.CreatedByID, saleReturn.ReturnNumber, approver.FullName())
	return nil
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

// GetApprovers returns all users who can approve requests for a tenant
// Approvers include: managers, assistant_managers, admins, and owners
func (w *WorkflowNotificationService) GetApprovers(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) ([]models.User, error) {
	var approvers []models.User

	query := w.db.WithContext(ctx).
		Where("tenant_id = ? AND role IN ? AND is_active = true", tenantID, ApproverRoles)

	// Note: We notify all approvers for the tenant, not just shop-specific ones
	// Managers/admins typically oversee multiple shops

	if err := query.Find(&approvers).Error; err != nil {
		return nil, fmt.Errorf("failed to get approvers: %w", err)
	}

	return approvers, nil
}

// NotifyGeneric sends a generic workflow notification to a specific user
func (w *WorkflowNotificationService) NotifyGeneric(ctx context.Context, tenantID, userID uuid.UUID, title, body string, category models.NotificationCategory, priority models.NotificationPriority, data map[string]interface{}) error {
	req := &models.SendNotificationRequest{
		UserID:   userID,
		Category: category,
		Priority: priority,
		Title:    title,
		Body:     body,
		Data:     data,
		Channels: []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
	}

	if _, err := w.notificationService.SendNotification(ctx, tenantID, userID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to send generic notification to %s: %v", userID, err)
		return err
	}

	return nil
}

// NotifyBulkApprovers sends a notification to all approvers for a tenant
func (w *WorkflowNotificationService) NotifyBulkApprovers(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, excludeUserID *uuid.UUID, title, body string, category models.NotificationCategory, priority models.NotificationPriority, data map[string]interface{}) error {
	approvers, err := w.GetApprovers(ctx, tenantID, shopID)
	if err != nil {
		return err
	}

	for _, approver := range approvers {
		// Skip excluded user (typically the creator)
		if excludeUserID != nil && approver.ID == *excludeUserID {
			continue
		}

		if err := w.NotifyGeneric(ctx, tenantID, approver.ID, title, body, category, priority, data); err != nil {
			log.Printf("[WORKFLOW] Failed to notify approver %s: %v", approver.ID, err)
			// Continue notifying other approvers even if one fails
		}
	}

	return nil
}

// =============================================================================
// MONEY COLLECTION WORKFLOW NOTIFICATIONS
// =============================================================================

// NotifyMoneyCollectionCreated notifies the target user when a money collection request is created
func (w *WorkflowNotificationService) NotifyMoneyCollectionCreated(ctx context.Context, tenantID, requesterID, targetUserID uuid.UUID, amount float64, requesterName string) error {
	title := "💰 Cash Request"
	body := fmt.Sprintf("₹%.0f requested by %s", amount, requesterName)

	req := &models.SendNotificationRequest{
		UserID:   targetUserID,
		Category: models.NotificationCategoryFinance,
		Priority: models.NotificationPriorityHigh,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":         "open_money_collection",
			"type":           "money_collection_request",
			"amount":         amount,
			"requester_id":   requesterID.String(),
			"requester_name": requesterName,
		},
		ActionURL: "/finance/collections",
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
	}

	if _, err := w.notificationService.SendNotification(ctx, tenantID, targetUserID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify target user %s for money collection: %v", targetUserID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified user %s about money collection request from %s", targetUserID, requesterName)
	return nil
}

// NotifyMoneyCollectionApproved notifies the requester when their money collection is approved
func (w *WorkflowNotificationService) NotifyMoneyCollectionApproved(ctx context.Context, tenantID, requesterID, approverID uuid.UUID, amount float64, approverName string) error {
	title := "✅ Cash Received"
	body := fmt.Sprintf("₹%.0f approved by %s", amount, approverName)

	req := &models.SendNotificationRequest{
		UserID:   requesterID,
		Category: models.NotificationCategoryFinance,
		Priority: models.NotificationPriorityNormal,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":        "open_money_collection",
			"type":          "money_collection_approved",
			"amount":        amount,
			"approved_by":   approverName,
			"approver_id":   approverID.String(),
			"approved_at":   time.Now().Format(time.RFC3339),
		},
		ActionURL: "/finance/collections",
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
	}

	if _, err := w.notificationService.SendNotification(ctx, tenantID, requesterID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify requester %s for approved collection: %v", requesterID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified user %s that collection was approved by %s", requesterID, approverName)
	return nil
}

// NotifyMoneyCollectionRejected notifies the requester when their money collection is rejected
func (w *WorkflowNotificationService) NotifyMoneyCollectionRejected(ctx context.Context, tenantID, requesterID, rejectorID uuid.UUID, amount float64, rejectorName, reason string) error {
	title := "❌ Cash Request Rejected"
	body := fmt.Sprintf("₹%.0f rejected: %s", amount, reason)

	req := &models.SendNotificationRequest{
		UserID:   requesterID,
		Category: models.NotificationCategoryFinance,
		Priority: models.NotificationPriorityHigh,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":      "open_money_collection",
			"type":        "money_collection_rejected",
			"amount":      amount,
			"rejected_by": rejectorName,
			"rejector_id": rejectorID.String(),
			"reason":      reason,
			"rejected_at": time.Now().Format(time.RFC3339),
		},
		ActionURL: "/finance/collections",
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
	}

	if _, err := w.notificationService.SendNotification(ctx, tenantID, requesterID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify requester %s for rejected collection: %v", requesterID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified user %s that collection was rejected by %s", requesterID, rejectorName)
	return nil
}

// =============================================================================
// EXPENSE WORKFLOW NOTIFICATIONS
// =============================================================================

// NotifyExpenseCreated notifies approvers when a new expense is submitted
func (w *WorkflowNotificationService) NotifyExpenseCreated(ctx context.Context, tenantID, creatorID uuid.UUID, expenseID uuid.UUID, amount float64, category, creatorName string) error {
	approvers, err := w.GetApprovers(ctx, tenantID, nil)
	if err != nil {
		return err
	}

	title := "📝 New Expense"
	body := fmt.Sprintf("₹%.0f %s by %s", amount, category, creatorName)

	for _, approver := range approvers {
		if approver.ID == creatorID {
			continue
		}

		req := &models.SendNotificationRequest{
			UserID:   approver.ID,
			Category: models.NotificationCategoryFinance,
			Priority: models.NotificationPriorityNormal,
			Title:    title,
			Body:     body,
			Data: map[string]interface{}{
				"action":       "open_expense_approval",
				"type":         "expense_created",
				"expense_id":   expenseID.String(),
				"amount":       amount,
				"category":     category,
				"created_by":   creatorName,
				"creator_id":   creatorID.String(),
			},
			ActionURL: fmt.Sprintf("/finance/expenses/%s", expenseID),
			Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
		}

		if _, err := w.notificationService.SendNotification(ctx, tenantID, approver.ID, req); err != nil {
			log.Printf("[WORKFLOW] Failed to notify approver %s for expense: %v", approver.ID, err)
		}
	}

	return nil
}

// NotifyExpenseApproved notifies the creator when their expense is approved
func (w *WorkflowNotificationService) NotifyExpenseApproved(ctx context.Context, tenantID, creatorID, approverID uuid.UUID, expenseID uuid.UUID, amount float64, approverName string) error {
	title := "✅ Expense Approved"
	body := fmt.Sprintf("₹%.0f approved by %s", amount, approverName)

	req := &models.SendNotificationRequest{
		UserID:   creatorID,
		Category: models.NotificationCategoryFinance,
		Priority: models.NotificationPriorityNormal,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":      "open_expense_details",
			"type":        "expense_approved",
			"expense_id":  expenseID.String(),
			"amount":      amount,
			"approved_by": approverName,
			"approver_id": approverID.String(),
			"approved_at": time.Now().Format(time.RFC3339),
		},
		ActionURL: fmt.Sprintf("/finance/expenses/%s", expenseID),
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
	}

	if _, err := w.notificationService.SendNotification(ctx, tenantID, creatorID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify creator %s for approved expense: %v", creatorID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified user %s that expense was approved by %s", creatorID, approverName)
	return nil
}

// NotifyExpenseRejected notifies the creator when their expense is rejected
func (w *WorkflowNotificationService) NotifyExpenseRejected(ctx context.Context, tenantID, creatorID, rejectorID uuid.UUID, expenseID uuid.UUID, amount float64, rejectorName, reason string) error {
	title := "❌ Expense Rejected"
	body := fmt.Sprintf("₹%.0f rejected: %s", amount, reason)

	req := &models.SendNotificationRequest{
		UserID:   creatorID,
		Category: models.NotificationCategoryFinance,
		Priority: models.NotificationPriorityHigh,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":      "open_expense_edit",
			"type":        "expense_rejected",
			"expense_id":  expenseID.String(),
			"amount":      amount,
			"rejected_by": rejectorName,
			"rejector_id": rejectorID.String(),
			"reason":      reason,
			"rejected_at": time.Now().Format(time.RFC3339),
		},
		ActionURL: fmt.Sprintf("/finance/expenses/%s/edit", expenseID),
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
	}

	if _, err := w.notificationService.SendNotification(ctx, tenantID, creatorID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify creator %s for rejected expense: %v", creatorID, err)
		return err
	}

	log.Printf("[WORKFLOW] Notified user %s that expense was rejected by %s", creatorID, rejectorName)
	return nil
}

// =============================================================================
// CASH SUBMISSION WORKFLOW NOTIFICATIONS
// =============================================================================

// NotifyCashSubmissionCreated notifies approvers when cash is submitted
func (w *WorkflowNotificationService) NotifyCashSubmissionCreated(ctx context.Context, tenantID, submitterID uuid.UUID, amount float64, shopName, submitterName string) error {
	approvers, err := w.GetApprovers(ctx, tenantID, nil)
	if err != nil {
		return err
	}

	title := fmt.Sprintf("💵 Cash Submitted • %s", shopName)
	body := fmt.Sprintf("₹%.0f from %s", amount, submitterName)

	for _, approver := range approvers {
		if approver.ID == submitterID {
			continue
		}

		req := &models.SendNotificationRequest{
			UserID:   approver.ID,
			Category: models.NotificationCategoryFinance,
			Priority: models.NotificationPriorityHigh,
			Title:    title,
			Body:     body,
			Data: map[string]interface{}{
				"action":        "open_cash_submissions",
				"type":          "cash_submission",
				"amount":        amount,
				"shop_name":     shopName,
				"submitted_by":  submitterName,
				"submitter_id":  submitterID.String(),
			},
			ActionURL: "/finance/cash/submissions",
			Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
		}

		if _, err := w.notificationService.SendNotification(ctx, tenantID, approver.ID, req); err != nil {
			log.Printf("[WORKFLOW] Failed to notify approver %s for cash submission: %v", approver.ID, err)
		}
	}

	return nil
}

// NotifyCashSubmissionApproved notifies the submitter when their cash submission is approved
func (w *WorkflowNotificationService) NotifyCashSubmissionApproved(ctx context.Context, tenantID, submitterID, approverID uuid.UUID, amount float64, approverName string) error {
	title := "✅ Cash Verified"
	body := fmt.Sprintf("₹%.0f verified by %s", amount, approverName)

	req := &models.SendNotificationRequest{
		UserID:   submitterID,
		Category: models.NotificationCategoryFinance,
		Priority: models.NotificationPriorityNormal,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":      "open_cash_history",
			"type":        "cash_submission_approved",
			"amount":      amount,
			"approved_by": approverName,
			"approver_id": approverID.String(),
			"approved_at": time.Now().Format(time.RFC3339),
		},
		ActionURL: "/finance/cash/history",
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
	}

	if _, err := w.notificationService.SendNotification(ctx, tenantID, submitterID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify submitter %s for approved cash: %v", submitterID, err)
		return err
	}

	return nil
}

// =============================================================================
// STOCK VERIFICATION WORKFLOW NOTIFICATIONS
// =============================================================================

// NotifyStockVerificationCreated notifies approvers when stock verification is submitted
func (w *WorkflowNotificationService) NotifyStockVerificationCreated(ctx context.Context, tenantID, creatorID uuid.UUID, verificationID uuid.UUID, shopName, creatorName string, discrepancyCount int) error {
	approvers, err := w.GetApprovers(ctx, tenantID, nil)
	if err != nil {
		return err
	}

	title := fmt.Sprintf("📦 Stock Verified • %s", shopName)
	body := fmt.Sprintf("%d discrepancies found by %s", discrepancyCount, creatorName)
	if discrepancyCount == 0 {
		body = fmt.Sprintf("No discrepancies • %s", creatorName)
	}

	for _, approver := range approvers {
		if approver.ID == creatorID {
			continue
		}

		req := &models.SendNotificationRequest{
			UserID:   approver.ID,
			Category: models.NotificationCategoryInventory,
			Priority: models.NotificationPriorityHigh,
			Title:    title,
			Body:     body,
			Data: map[string]interface{}{
				"action":           "open_stock_verification",
				"type":             "stock_verification_created",
				"verification_id":  verificationID.String(),
				"shop_name":        shopName,
				"discrepancy_count": discrepancyCount,
				"created_by":       creatorName,
				"creator_id":       creatorID.String(),
			},
			ActionURL: fmt.Sprintf("/inventory/verifications/%s", verificationID),
			Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
		}

		if _, err := w.notificationService.SendNotification(ctx, tenantID, approver.ID, req); err != nil {
			log.Printf("[WORKFLOW] Failed to notify approver %s for stock verification: %v", approver.ID, err)
		}
	}

	return nil
}

// NotifyStockVerificationApproved notifies the creator when their stock verification is approved
func (w *WorkflowNotificationService) NotifyStockVerificationApproved(ctx context.Context, tenantID, creatorID, approverID uuid.UUID, verificationID uuid.UUID, approverName string) error {
	title := "✅ Verification Approved"
	body := fmt.Sprintf("Stock count approved by %s", approverName)

	req := &models.SendNotificationRequest{
		UserID:   creatorID,
		Category: models.NotificationCategoryInventory,
		Priority: models.NotificationPriorityNormal,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":          "open_stock_verification",
			"type":            "stock_verification_approved",
			"verification_id": verificationID.String(),
			"approved_by":     approverName,
			"approver_id":     approverID.String(),
			"approved_at":     time.Now().Format(time.RFC3339),
		},
		ActionURL: fmt.Sprintf("/inventory/verifications/%s", verificationID),
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
	}

	if _, err := w.notificationService.SendNotification(ctx, tenantID, creatorID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify creator %s for approved verification: %v", creatorID, err)
		return err
	}

	return nil
}

// NotifyStockVerificationRejected notifies the creator when their stock verification is rejected
func (w *WorkflowNotificationService) NotifyStockVerificationRejected(ctx context.Context, tenantID, creatorID, rejectorID uuid.UUID, verificationID uuid.UUID, rejectorName, reason string) error {
	title := "❌ Verification Rejected"
	body := fmt.Sprintf("Rejected: %s", reason)

	req := &models.SendNotificationRequest{
		UserID:   creatorID,
		Category: models.NotificationCategoryInventory,
		Priority: models.NotificationPriorityHigh,
		Title:    title,
		Body:     body,
		Data: map[string]interface{}{
			"action":          "open_stock_verification",
			"type":            "stock_verification_rejected",
			"verification_id": verificationID.String(),
			"rejected_by":     rejectorName,
			"rejector_id":     rejectorID.String(),
			"reason":          reason,
			"rejected_at":     time.Now().Format(time.RFC3339),
		},
		ActionURL: fmt.Sprintf("/inventory/verifications/%s", verificationID),
		Channels:  []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush},
	}

	if _, err := w.notificationService.SendNotification(ctx, tenantID, creatorID, req); err != nil {
		log.Printf("[WORKFLOW] Failed to notify creator %s for rejected verification: %v", creatorID, err)
		return err
	}

	return nil
}

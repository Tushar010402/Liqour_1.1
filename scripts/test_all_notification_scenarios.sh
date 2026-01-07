#!/bin/bash
# =============================================================================
# LiquorPro - Complete Notification Scenarios Test
# Tests all notification categories with in-app and push channels
# =============================================================================

BASE_URL="${BASE_URL:-http://localhost:8090}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "$1"; }
header() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

PASSED=0
FAILED=0
NOTIFICATION_IDS=()

test_notification() {
    local category=$1
    local title=$2
    local body=$3
    local priority=$4
    local data=$5

    log "${BLUE}Testing: $title${NC}"

    RESP=$(curl -s -X POST "$BASE_URL/api/notifications/send" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"user_id\": \"$USER_ID\",
            \"category\": \"$category\",
            \"priority\": \"$priority\",
            \"title\": \"$title\",
            \"body\": \"$body\",
            \"channels\": [\"in_app\", \"push\"],
            \"data\": $data
        }")

    SUCCESS=$(echo "$RESP" | jq -r '.success // false')
    NOTIF_ID=$(echo "$RESP" | jq -r '.data.id // empty')

    if [ "$SUCCESS" = "true" ] && [ -n "$NOTIF_ID" ]; then
        log "${GREEN}  ✓ SENT${NC} - ID: ${NOTIF_ID:0:8}..."
        NOTIFICATION_IDS+=("$NOTIF_ID")
        ((PASSED++))
        return 0
    else
        ERROR=$(echo "$RESP" | jq -r '.error // "Unknown error"')
        log "${RED}  ✗ FAILED${NC} - $ERROR"
        ((FAILED++))
        return 1
    fi
}

# =============================================================================
# Authentication
# =============================================================================
header "AUTHENTICATION"

log "Sending OTP..."
curl -s -X POST "$BASE_URL/api/auth/send-otp" \
    -H "Content-Type: application/json" \
    -d '{"mobile":"+916388016072"}' > /dev/null

log "Verifying OTP..."
AUTH_RESP=$(curl -s -X POST "$BASE_URL/api/auth/verify-otp" \
    -H "Content-Type: application/json" \
    -d '{"mobile":"+916388016072","otp":"011001"}')

TOKEN=$(echo "$AUTH_RESP" | jq -r '.token // empty')
USER_ID=$(echo "$AUTH_RESP" | jq -r '.user.id // empty')
TENANT_ID=$(echo "$AUTH_RESP" | jq -r '.user.tenant_id // empty')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    log "${RED}Authentication failed!${NC}"
    exit 1
fi

log "${GREEN}✓ Authenticated${NC}"
log "  User ID: $USER_ID"
log "  Tenant ID: $TENANT_ID"

# =============================================================================
# Device Registration (for Push)
# =============================================================================
header "DEVICE REGISTRATION"

# Register a test device for push notifications
FCM_TOKEN="test_fcm_token_$(date +%s)"
DEVICE_RESP=$(curl -s -X POST "$BASE_URL/api/notifications/register-device" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"token\": \"$FCM_TOKEN\",
        \"device_id\": \"test_device_001\",
        \"platform\": \"android\",
        \"device_name\": \"Test Android Phone\"
    }")

if echo "$DEVICE_RESP" | jq -e '.success' > /dev/null 2>&1; then
    log "${GREEN}✓ Device registered for push${NC}"
    log "  FCM Token: ${FCM_TOKEN:0:20}..."
else
    log "${YELLOW}⚠ Device registration response: $(echo "$DEVICE_RESP" | jq -c '.')${NC}"
fi

# =============================================================================
# SCENARIO 1: SALES NOTIFICATIONS
# =============================================================================
header "SCENARIO 1: SALES NOTIFICATIONS"

test_notification "sales" \
    "🎉 New Sale Completed" \
    "Sale #INV-2024-1234 completed successfully. Amount: ₹15,500" \
    "normal" \
    '{"sale_id": "sale_123", "invoice_number": "INV-2024-1234", "amount": 15500, "customer": "ABC Store"}'

test_notification "sales" \
    "⚠️ Sale Cancelled" \
    "Sale #INV-2024-1235 was cancelled by customer request" \
    "high" \
    '{"sale_id": "sale_124", "invoice_number": "INV-2024-1235", "reason": "customer_request"}'

test_notification "sales" \
    "📊 Daily Sales Target Achieved" \
    "Congratulations! You've achieved 120% of today's sales target (₹50,000/₹41,666)" \
    "normal" \
    '{"target": 41666, "achieved": 50000, "percentage": 120}'

test_notification "sales" \
    "🔔 Credit Sale Reminder" \
    "Credit sale to XYZ Mart (₹25,000) is due for collection today" \
    "high" \
    '{"customer_id": "cust_456", "customer_name": "XYZ Mart", "amount": 25000, "due_date": "2025-12-19"}'

# =============================================================================
# SCENARIO 2: INVENTORY NOTIFICATIONS
# =============================================================================
header "SCENARIO 2: INVENTORY NOTIFICATIONS"

test_notification "inventory" \
    "🔴 Low Stock Alert" \
    "Royal Stag 750ml is running low. Current stock: 5 units (Threshold: 10)" \
    "high" \
    '{"product_id": "prod_001", "product_name": "Royal Stag 750ml", "current_stock": 5, "threshold": 10}'

test_notification "inventory" \
    "📦 Stock Received" \
    "New stock received: 50 units of Johnnie Walker Black Label" \
    "normal" \
    '{"product_id": "prod_002", "product_name": "Johnnie Walker Black Label", "quantity": 50, "po_number": "PO-2024-789"}'

test_notification "inventory" \
    "⚠️ Expiring Products" \
    "3 products expiring within 30 days. Please review and take action." \
    "high" \
    '{"expiring_count": 3, "days_threshold": 30, "action_url": "/inventory/expiring"}'

test_notification "inventory" \
    "📋 Inventory Variance Detected" \
    "Physical count differs from system: Absolut Vodka (System: 20, Physical: 18)" \
    "high" \
    '{"product_id": "prod_003", "product_name": "Absolut Vodka", "system_count": 20, "physical_count": 18, "variance": -2}'

test_notification "inventory" \
    "🐢 Slow Moving Inventory" \
    "5 products have not sold in the last 60 days. Review for potential markdowns." \
    "normal" \
    '{"slow_moving_count": 5, "days_threshold": 60}'

# =============================================================================
# SCENARIO 3: FINANCE NOTIFICATIONS
# =============================================================================
header "SCENARIO 3: FINANCE NOTIFICATIONS"

test_notification "finance" \
    "💰 Settlement Reminder" \
    "Daily settlement pending. Total cash: ₹45,000. Please complete by 8 PM." \
    "high" \
    '{"cash_amount": 45000, "deadline": "20:00", "shop_id": "shop_001"}'

test_notification "finance" \
    "✅ Settlement Completed" \
    "Settlement #STL-2024-567 completed successfully. Amount: ₹45,000" \
    "normal" \
    '{"settlement_id": "stl_567", "amount": 45000, "method": "bank_deposit"}'

test_notification "finance" \
    "🔴 Cash Shortage Alert" \
    "Cash shortage detected: Expected ₹50,000, Actual ₹48,500. Difference: ₹1,500" \
    "critical" \
    '{"expected": 50000, "actual": 48500, "shortage": 1500}'

test_notification "finance" \
    "💳 Credit Overdue" \
    "3 customers have overdue credit totaling ₹75,000. Oldest: 15 days overdue." \
    "high" \
    '{"overdue_count": 3, "total_amount": 75000, "oldest_days": 15}'

test_notification "finance" \
    "📅 Vendor Payment Due" \
    "Payment to supplier ABC Distributors (₹1,25,000) is due in 3 days" \
    "normal" \
    '{"vendor_id": "vendor_001", "vendor_name": "ABC Distributors", "amount": 125000, "due_date": "2025-12-22"}'

test_notification "finance" \
    "💵 Cash Collection Reminder" \
    "Pending cash collection from 5 credit customers. Total: ₹35,000" \
    "normal" \
    '{"pending_count": 5, "total_amount": 35000}'

# =============================================================================
# SCENARIO 4: SYSTEM NOTIFICATIONS
# =============================================================================
header "SCENARIO 4: SYSTEM NOTIFICATIONS"

test_notification "system" \
    "🔐 New Login Detected" \
    "New login from Android device in Mumbai, India" \
    "normal" \
    '{"device": "Android", "location": "Mumbai, India", "ip": "103.x.x.x", "timestamp": "2025-12-19T21:00:00Z"}'

test_notification "system" \
    "🔄 App Update Available" \
    "LiquorPro v2.5.0 is available with new features and bug fixes" \
    "low" \
    '{"version": "2.5.0", "release_notes_url": "/updates/2.5.0"}'

test_notification "system" \
    "⚙️ Scheduled Maintenance" \
    "System maintenance scheduled for Dec 25, 2025, 2:00 AM - 4:00 AM IST" \
    "normal" \
    '{"start_time": "2025-12-25T02:00:00+05:30", "end_time": "2025-12-25T04:00:00+05:30"}'

test_notification "system" \
    "📢 Important Announcement" \
    "New tax rates effective from Jan 1, 2026. Please review updated pricing." \
    "high" \
    '{"announcement_id": "ann_001", "effective_date": "2026-01-01"}'

# =============================================================================
# SCENARIO 5: REMINDER NOTIFICATIONS
# =============================================================================
header "SCENARIO 5: REMINDER NOTIFICATIONS"

test_notification "reminder" \
    "⏰ Daily Sales Report" \
    "Time to submit your daily sales report. Deadline: 6:00 PM" \
    "normal" \
    '{"reminder_type": "daily_sales", "deadline": "18:00"}'

test_notification "reminder" \
    "📝 Audit Reminder" \
    "Weekly inventory audit is scheduled for today. Complete before EOD." \
    "high" \
    '{"reminder_type": "audit", "audit_type": "weekly_inventory"}'

test_notification "reminder" \
    "🏪 Shop Opening Checklist" \
    "Complete daily opening checklist: Stock check, Cash verification, Display setup" \
    "normal" \
    '{"reminder_type": "opening_checklist", "items": ["stock_check", "cash_verify", "display_setup"]}'

# =============================================================================
# SCENARIO 6: ALARM NOTIFICATIONS
# =============================================================================
header "SCENARIO 6: ALARM NOTIFICATIONS"

test_notification "alarm" \
    "🚨 Critical: Multiple Low Stock Items" \
    "15 products are below reorder level. Immediate attention required!" \
    "critical" \
    '{"alarm_code": "low_stock_critical", "product_count": 15, "severity": "critical"}'

test_notification "alarm" \
    "⚠️ Unusual Sales Pattern" \
    "Unusually high void transactions detected (12 voids in last hour)" \
    "high" \
    '{"alarm_code": "unusual_activity", "void_count": 12, "time_period": "1 hour"}'

test_notification "alarm" \
    "🔒 Security Alert" \
    "Multiple failed login attempts detected from IP 192.168.1.100" \
    "critical" \
    '{"alarm_code": "security_breach", "attempt_count": 5, "ip_address": "192.168.1.100"}'

# =============================================================================
# SCENARIO 7: APPROVAL NOTIFICATIONS
# =============================================================================
header "SCENARIO 7: APPROVAL NOTIFICATIONS"

test_notification "approval" \
    "📋 Expense Approval Required" \
    "New expense request from John Doe: ₹5,000 for Store Maintenance" \
    "high" \
    '{"request_type": "expense", "requester": "John Doe", "amount": 5000, "category": "maintenance"}'

test_notification "approval" \
    "✅ Leave Request Approved" \
    "Your leave request for Dec 25-26 has been approved by Manager" \
    "normal" \
    '{"request_type": "leave", "dates": "Dec 25-26, 2025", "approved_by": "Manager"}'

test_notification "approval" \
    "📦 Purchase Order Pending" \
    "PO #PO-2024-890 (₹2,50,000) requires your approval" \
    "high" \
    '{"request_type": "purchase_order", "po_number": "PO-2024-890", "amount": 250000, "vendor": "XYZ Suppliers"}'

# =============================================================================
# Check Push Delivery Status
# =============================================================================
header "PUSH DELIVERY VERIFICATION"

log "Checking recent push deliveries in finance service logs..."
sleep 2

PUSH_LOGS=$(sudo docker logs liquorpro-finance-prod --since 2m 2>&1 | grep -i "firebase\|push\|FCM" | tail -10)

if [ -n "$PUSH_LOGS" ]; then
    log "${GREEN}Recent Push Activity:${NC}"
    echo "$PUSH_LOGS" | while read line; do
        log "  $line"
    done
else
    log "${YELLOW}No push activity in logs (test FCM token won't deliver to real device)${NC}"
fi

# =============================================================================
# Verify Notifications in Database
# =============================================================================
header "DATABASE VERIFICATION"

log "Querying recent notifications..."
NOTIF_COUNT=$(curl -s "$BASE_URL/api/notifications?page_size=100" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.data | length // 0')

log "Total notifications for user: $NOTIF_COUNT"

# Get counts by category
log "\nNotification counts by category:"
COUNTS_RESP=$(curl -s "$BASE_URL/api/notifications/counts" -H "Authorization: Bearer $TOKEN")
echo "$COUNTS_RESP" | jq '.'

# =============================================================================
# Summary
# =============================================================================
header "TEST SUMMARY"

TOTAL=$((PASSED + FAILED))
log "Total Notifications Sent: $TOTAL"
log "${GREEN}Passed: $PASSED${NC}"
log "${RED}Failed: $FAILED${NC}"

if [ ${#NOTIFICATION_IDS[@]} -gt 0 ]; then
    log "\nNotification IDs created:"
    for id in "${NOTIFICATION_IDS[@]}"; do
        log "  - $id"
    done
fi

log "\n${BLUE}Notification Categories Tested:${NC}"
log "  1. Sales (4 scenarios)"
log "  2. Inventory (5 scenarios)"
log "  3. Finance (6 scenarios)"
log "  4. System (4 scenarios)"
log "  5. Reminder (3 scenarios)"
log "  6. Alarm (3 scenarios)"
log "  7. Approval (3 scenarios)"

log "\n${CYAN}To view notifications on mobile app:${NC}"
log "  1. Register device with real FCM token"
log "  2. Navigate to Notifications screen"
log "  3. Pull to refresh"

[ $FAILED -eq 0 ] && exit 0 || exit 1

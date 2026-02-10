# Finance API

## Overview

The Finance API provides endpoints for cash management, money collections, expenses, vendor management, reconciliation, tips, fraud detection, audit management, notifications, and alarms.

**Base URL**: `https://new.v2.floelife.in/api`

---

## Vendors

### List Vendors

#### GET /vendors

List all vendors with optional filtering.

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| shop_id | UUID | Filter by shop |
| search | string | Search by name |
| page | int | Page number |
| per_page | int | Items per page |

---

### Create Vendor

#### POST /vendors

Create a new vendor. Role required: `manager` or `admin`.

**Request:**
```json
{
  "name": "ABC Distributors",
  "contact_person": "John Doe",
  "phone": "9876543210",
  "email": "abc@distributors.com",
  "address": "123 Main Street",
  "gst_number": "22AAAAA0000A1Z5",
  "pan_number": "AAAAA0000A"
}
```

---

### Get Vendor

#### GET /vendors/:id

Get vendor details including transaction history.

---

### Update Vendor

#### PUT /vendors/:id

Update vendor information. Role required: `manager` or `admin`.

---

### Delete Vendor

#### DELETE /vendors/:id

Delete a vendor. Role required: `admin`.

---

### Get Vendor Ledger

#### GET /vendors/:id/ledger

Get complete transaction ledger for a vendor with running balance.

---

### Get Vendor Transactions

#### GET /vendors/:id/transactions

Get transaction history for a vendor.

---

### Create Vendor Transaction

#### POST /vendors/transactions

Record a transaction with a vendor (payment or purchase). Role required: `manager` or `admin`.

**Request:**
```json
{
  "vendor_id": "vendor-uuid",
  "amount": 50000.00,
  "type": "payment",
  "payment_method": "bank_transfer",
  "reference_number": "TXN123456",
  "notes": "Monthly payment"
}
```

---

### Add Vendor Bank Account

#### POST /vendors/:id/bank-accounts

Add a bank account for a vendor. Role required: `manager` or `admin`.

---

## Expenses

### List Expenses

#### GET /expenses

List expenses with filtering.

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| shop_id | UUID | Filter by shop |
| status | string | pending, approved, rejected |
| start_date | date | Start date (YYYY-MM-DD) |
| end_date | date | End date (YYYY-MM-DD) |
| category_id | UUID | Filter by expense category |

---

### Create Expense

#### POST /expenses

Create a new expense record. Role required: `salesman`, `manager`, or `admin`.

**Request:**
```json
{
  "shop_id": "shop-uuid",
  "header_id": "expense-category-uuid",
  "amount": 500.00,
  "description": "Transport charges",
  "receipt_url": "https://storage.example.com/receipts/xyz.jpg"
}
```

---

### Get Expense

#### GET /expenses/:id

Get expense details.

---

### Update Expense

#### PUT /expenses/:id

Update a pending expense. Role required: `manager` or `admin`.

---

### Delete Expense

#### DELETE /expenses/:id

Delete a pending expense. Role required: `admin`.

---

## Expense Categories

### List Expense Categories

#### GET /expense-categories

List all expense categories.

---

### Create Expense Category

#### POST /expense-categories

Create a new expense category. Role required: `manager` or `admin`.

---

## Money Collections (15-Minute Deadline)

Money collections are automatically created when daily sales are approved. The assigned user has a **configurable deadline** (default 15 minutes, set via `TenantSettings.MoneyCollectionDeadlineMinutes`) to collect and record the cash.

### List Money Collections

#### GET /assistant-manager/money-collections

List money collections with filtering. Role required: `assistant_manager`, `manager`, or `admin`.

**Aliases:** `GET /collections`, `GET /cash-requests`, `GET /pending-requests`, `GET /cash/requests`, `GET /cash/collections`

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| shop_id | UUID | Filter by shop |
| status | string | pending, approved, rejected |
| collector_id | UUID | Filter by assigned collector |
| start_date | date | Start date |
| end_date | date | End date |

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": "collection-uuid",
      "daily_record_id": "dsr-uuid",
      "shop": {
        "id": "shop-uuid",
        "name": "Main Street Store"
      },
      "salesman": {
        "id": "salesman-uuid",
        "name": "John Doe"
      },
      "collector": {
        "id": "collector-uuid",
        "name": "Jane Smith"
      },
      "amount": 45000.00,
      "status": "pending",
      "deadline": "2025-01-11T18:15:00Z",
      "is_overdue": false,
      "created_at": "2025-01-11T18:00:00Z"
    }
  ]
}
```

---

### Create Money Collection

#### POST /assistant-manager/money-collections

Create a money collection request. Role required: `assistant_manager`, `manager`, or `admin`.

**Alias:** `POST /cash/request`

---

### Get Money Collection

#### GET /assistant-manager/money-collections/:id

Get collection details including deadline status.

**Alias:** `GET /cash/requests/:id`

---

### Approve Money Collection

#### POST /assistant-manager/money-collections/:id/approve

Approve a money collection. Role required: `manager` or `admin`.

**Alias:** `POST /cash/requests/:id/approve`

---

### Reject Money Collection

#### POST /assistant-manager/money-collections/:id/reject

Reject a money collection. Role required: `manager` or `admin`.

**Alias:** `POST /cash/requests/:id/reject`

---

## Cash Management

### Get Cash Balance

#### GET /cash/balance

Get current cash balance for shop or user.

**Alias:** `GET /dashboard/cash-balance`

---

### Get Cash History

#### GET /cash/history

Get cash transaction history.

**Alias:** `GET /reports/cash-history`

---

### Get Team Cash Balances

#### GET /cash/team-balances

Get cash balances for all team members. Role required: `manager` or `admin`.

---

### Get Tenant Users (for Cash Management)

#### GET /cash/tenant-users

Get tenant users for cash management dropdowns.

**Alias:** `GET /cash/users`

---

### Reconcile Balances

#### POST /cash/reconcile-balances

Admin: Recalculate all user balances.

---

### Upload Receipt

#### POST /cash/upload-receipt

Upload receipt image for a transaction.

**Alias:** `POST /upload/receipt`

---

### Admin Cash Balance Management

#### POST /cash/admin/set-balance

Set individual user balance. Role required: `admin` or `owner`.

---

#### POST /cash/admin/bulk-reset

Bulk reset user balances. Role required: `admin` or `owner`.

---

## Cash Deposits (Bank Submissions)

### Submit Cash to Bank

#### POST /cash/submit

Submit cash for bank deposit.

---

### List Cash Deposits

#### GET /cash/deposits

List cash deposits.

**Alias:** `GET /cash/submissions`

---

### Get Pending Deposits Count

#### GET /cash/deposits/pending/count

Get count of pending deposits for dashboard badge.

---

### Get Cash Deposit

#### GET /cash/deposits/:id

Get specific deposit details.

**Alias:** `GET /cash/submissions/:id`

---

### Approve Cash Deposit

#### POST /cash/deposits/:id/approve

Approve a cash deposit. Role required: `manager` or `admin`.

**Alias:** `POST /cash/submissions/:id/approve`

---

### Reject Cash Deposit

#### POST /cash/deposits/:id/reject

Reject a cash deposit. Role required: `manager` or `admin`.

**Alias:** `POST /cash/submissions/:id/reject`

---

## Bank Accounts

### List Bank Accounts

#### GET /bank-accounts

List all bank accounts.

---

### Create Bank Account

#### POST /bank-accounts

Create a new bank account.

**Request:**
```json
{
  "bank_name": "State Bank of India",
  "account_number": "1234567890",
  "ifsc_code": "SBIN0001234",
  "account_type": "current",
  "branch": "Main Branch"
}
```

---

### Get Bank Account

#### GET /bank-accounts/:id

Get bank account details.

---

### Bank Deposits

#### GET /bank-deposits

List bank deposits.

#### POST /bank-deposits

Create a bank deposit.

#### GET /bank-deposits/:id

Get deposit details.

#### POST /bank-deposits/:id/approve

Approve a deposit.

#### POST /bank-deposits/:id/reject

Reject a deposit.

---

## Reconciliations

### List Reconciliations

#### GET /reconciliations

List reconciliation records.

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| shop_id | UUID | Filter by shop |
| status | string | pending, completed, approved |
| start_date | date | Start date |
| end_date | date | End date |

---

### Create Reconciliation

#### POST /reconciliations

Create a new reconciliation session.

**Request:**
```json
{
  "shop_id": "shop-uuid",
  "reconciliation_date": "2025-01-11",
  "opening_cash": 5000.00,
  "expected_cash": 50000.00,
  "actual_cash": 49800.00,
  "notes": "Minor shortfall due to rounding"
}
```

---

### Get Reconciliation

#### GET /reconciliations/:id

Get reconciliation details.

---

### Complete Reconciliation

#### POST /reconciliations/:id/complete

Mark reconciliation as complete.

---

### Approve Reconciliation

#### POST /reconciliations/:id/approve

Approve a completed reconciliation.

---

## Stock Verification

### List Verifications

#### GET /stock-verification

List stock verification records.

---

### Create Verification

#### POST /stock-verification

Create a stock verification session.

---

### Get Verification

#### GET /stock-verification/:id

Get verification details.

---

### Approve Verification

#### POST /stock-verification/:id/approve

Approve verification results.

---

### Reject Verification

#### POST /stock-verification/:id/reject

Reject verification results.

---

### Get Stock Audit Logs

#### GET /stock-audit-logs

Get stock audit log history.

---

## Executive Finance

### List Executive Finance

#### GET /executive-finance

List executive finance records (cash handovers, expense claims).

---

### Create Executive Finance

#### POST /executive-finance

Create an executive finance record.

---

### Get Executive Finance

#### GET /executive-finance/:id

Get executive finance details.

---

### Approve Executive Finance

#### POST /executive-finance/:id/approve

Approve an executive finance record. Role required: `executive`, `manager`, or `admin`.

---

### Reject Executive Finance

#### POST /executive-finance/:id/reject

Reject an executive finance record. Role required: `executive`, `manager`, or `admin`.

---

## Assistant Manager Finance

### List AM Expenses

#### GET /assistant-manager/expenses

List assistant manager expenses.

---

### Create AM Expense

#### POST /assistant-manager/expenses

Create an assistant manager expense.

---

### List AM Finance Records

#### GET /assistant-manager/finance

List assistant manager finance records.

---

### Create AM Finance Record

#### POST /assistant-manager/finance

Create an assistant manager finance record.

---

## Tenant Settings

### Get Tenant Settings

#### GET /tenant-settings

Get tenant-specific settings (including money collection deadline).

---

### Update Tenant Settings

#### PUT /tenant-settings

Update tenant settings.

---

## Tips Management

### Record Tip

#### POST /tips

Record a new tip.

---

### List Tips

#### GET /tips

List tip records.

---

### Get My Tips

#### GET /tips/my

Get current user's tips.

---

### Get Tip

#### GET /tips/:id

Get tip details.

---

### Update Tip

#### PUT /tips/:id

Update tip record.

---

### Delete Tip

#### DELETE /tips/:id

Delete tip record.

---

### Approve Tip

#### POST /tips/:id/approve

Approve a tip.

---

### Reject Tip

#### POST /tips/:id/reject

Reject a tip.

---

### Tip Pools

#### GET /tips/pools

List tip pools.

#### POST /tips/pools

Create a tip pool.

#### GET /tips/pools/:id

Get pool details.

#### PUT /tips/pools/:id

Update tip pool.

#### DELETE /tips/pools/:id

Delete tip pool.

---

### Tip Payouts

#### GET /tips/payouts

List tip payouts.

#### POST /tips/payouts

Create a tip payout.

#### GET /tips/payouts/:id

Get payout details.

#### POST /tips/payouts/:id/complete

Complete a tip payout.

---

### Tips Analytics

#### GET /tips/dashboard

Get tips dashboard.

#### GET /tips/analytics

Get tips analytics.

#### GET /tips/summary

Get tips summary.

---

## Fraud Detection Module

### Detection Dashboard

#### GET /detection/dashboard

Get detection dashboard overview.

---

### Detection Analytics

#### GET /detection/analytics

Get detection analytics data.

---

### Detection Alerts

#### GET /detection/alerts

List fraud detection alerts.

#### GET /detection/alerts/:id

Get alert details.

#### POST /detection/alerts/:id/acknowledge

Acknowledge an alert.

#### POST /detection/alerts/:id/resolve

Resolve an alert.

#### POST /detection/alerts/:id/escalate

Escalate an alert.

---

### Investigations

#### GET /detection/investigations

List investigations.

#### POST /detection/investigations

Create an investigation.

#### GET /detection/investigations/:id

Get investigation details.

#### PUT /detection/investigations/:id

Update investigation.

#### POST /detection/investigations/:id/close

Close an investigation.

---

### Detection Thresholds

#### GET /detection/thresholds

Get detection threshold configuration.

#### PUT /detection/thresholds

Update detection thresholds.

#### POST /detection/thresholds/reset

Reset thresholds to defaults.

---

### Manual Detection Triggers

#### POST /detection/analyze

Trigger detection analysis.

#### POST /detection/batch-analyze

Batch detection analysis.

---

### Detection Reports

#### GET /detection/reports/trends

Get detection trends report.

#### GET /detection/reports/user-risk

Get user risk report.

---

## Audit Module

### Audit Dashboard

#### GET /audit/dashboard

Get audit dashboard overview.

---

### Audit Schedules

#### GET /audit/schedules

List audit schedules.

#### POST /audit/schedules

Create an audit schedule.

#### GET /audit/schedules/:id

Get schedule details.

#### PUT /audit/schedules/:id

Update schedule.

#### DELETE /audit/schedules/:id

Delete schedule.

---

### Audit Sessions

#### GET /audit/sessions

List audit sessions.

#### POST /audit/sessions

Create an audit session.

#### GET /audit/sessions/:id

Get session details.

#### PUT /audit/sessions/:id

Update session.

#### POST /audit/sessions/:id/complete

Complete audit session.

#### POST /audit/sessions/:id/approve

Approve audit session.

#### POST /audit/sessions/:id/reject

Reject audit session.

---

### Cash Count Records

#### POST /audit/sessions/:id/cash-count

Record a cash count within an audit session.

#### GET /audit/sessions/:id/cash-counts

Get cash counts for an audit session.

---

### Audit Findings

#### GET /audit/findings

List audit findings.

#### POST /audit/findings

Create an audit finding.

#### GET /audit/findings/:id

Get finding details.

#### PUT /audit/findings/:id

Update finding.

#### POST /audit/findings/:id/resolve

Resolve finding.

---

### Audit Reports

#### GET /audit/reports/compliance

Get compliance report.

#### GET /audit/reports/history

Get audit history.

#### GET /audit/reports/trends

Get audit trends.

---

### Quick Audit Actions

#### POST /audit/quick-count

Quick cash count.

#### GET /audit/due-today

Get audits due today.

---

## Notifications

### Device Registration

#### POST /notifications/register-device

Register device for push notifications (FCM token).

**Alias:** `POST /notifications/devices`

---

#### DELETE /notifications/unregister-device

Unregister device.

**Alias:** `DELETE /notifications/devices`

---

### User Notifications

#### GET /notifications

List notifications for current user.

#### GET /notifications/counts

Get notification counts (read/unread).

#### GET /notifications/unread

Get unread notifications.

---

### Mark as Read

#### POST /notifications/mark-read

Mark specific notifications as read.

**Alias:** `POST /notifications/read`

---

#### POST /notifications/mark-all-read

Mark all notifications as read.

**Alias:** `POST /notifications/read-all`

---

#### PATCH /notifications/:id/read

Mark single notification as read.

---

#### DELETE /notifications/:id

Delete a notification.

---

### Notification Preferences

#### GET /notifications/preferences

Get notification preferences.

#### PUT /notifications/preferences

Update notification preferences.

---

### WhatsApp Integration

#### POST /notifications/whatsapp/opt-in

Opt-in to WhatsApp notifications.

#### POST /notifications/whatsapp/opt-out

Opt-out of WhatsApp notifications.

#### GET /notifications/whatsapp/status

Get WhatsApp notification status.

---

### Admin Notification Management

#### POST /notifications/send

Send a notification.

#### POST /notifications/send-bulk

Send bulk notifications.

#### POST /notifications/broadcast

Broadcast notification to all users.

---

### Notification Templates

#### GET /notifications/templates

List notification templates.

#### POST /notifications/templates

Create notification template.

#### PUT /notifications/templates/:id

Update template.

#### DELETE /notifications/templates/:id

Delete template.

---

#### GET /notifications/stats

Get notification statistics (admin).

---

## Finance Matrix (Executive Dashboard)

### Get Finance Matrix

#### GET /matrix

Get finance matrix data.

---

### Matrix Insights and Alerts

#### GET /matrix/insights

Get matrix insights.

#### GET /matrix/alerts

Get matrix alerts.

#### POST /matrix/alerts/:id/acknowledge

Acknowledge a matrix alert.

#### POST /matrix/alerts/:id/resolve

Resolve a matrix alert.

---

### Matrix Dashboard

#### GET /matrix/dashboard

Get comprehensive matrix dashboard.

---

### Daily Financial Metrics

#### GET /matrix/daily-metrics

Get daily financial metrics.

#### GET /matrix/daily-metrics/history

Get daily metrics history.

---

### Cash Holdings

#### GET /matrix/cash-holdings

Get cash holdings.

#### GET /matrix/cash-holdings/by-user

Get holdings by user.

#### GET /matrix/cash-holdings/by-location

Get holdings by location.

---

### Cash Flow Analysis

#### GET /matrix/cash-flow

Get matrix cash flow.

#### GET /matrix/cash-flow/forecast

Get cash flow forecast.

---

### Module Integrations

#### GET /matrix/tips-overview

Get tips overview from Tips module.

#### GET /matrix/risk-metrics

Get risk metrics from Detection module.

#### GET /matrix/risk-score

Get overall risk score.

#### GET /matrix/compliance-metrics

Get compliance metrics from Audit module.

---

### Team Performance

#### GET /matrix/team-performance

Get team performance analytics.

#### GET /matrix/user-performance/:user_id

Get specific user's performance.

---

### Trend Analysis

#### GET /matrix/trends/weekly

Get weekly trends.

#### GET /matrix/trends/monthly

Get monthly trends.

---

### Export and Reporting

#### GET /matrix/export

Export matrix data.

#### POST /matrix/generate-report

Generate matrix report.

---

## Dashboard Metrics

### Get Dashboard Metrics

#### GET /dashboard/metrics

Get dashboard metrics. Role required: `manager`, `assistant_manager`, or `admin`.

---

### Get Payment Details

#### GET /dashboard/metrics/payment/details

Get payment details for dashboard.

---

### Get Purchase Details

#### GET /dashboard/metrics/purchase/details

Get purchase details for dashboard.

---

### Get Sale Details

#### GET /dashboard/metrics/sale/details

Get sale details for dashboard.

---

### Get Expense Details

#### GET /dashboard/metrics/expense/details

Get expense details for dashboard.

---

## Alarm System

### Alarm Definitions

#### GET /alarms/definitions

Get alarm definitions (read-only).

#### GET /alarms/definitions/:code

Get specific alarm definition by code.

---

### Alarm Configurations

#### GET /alarms/configurations

Get alarm configurations.

#### GET /alarms/configurations/:code

Get specific alarm configuration.

#### PUT /alarms/configurations

Update alarm configuration.

---

### Alarm Instances

#### GET /alarms

List active alarms.

#### GET /alarms/:id

Get alarm details.

#### POST /alarms/:id/acknowledge

Acknowledge an alarm.

#### POST /alarms/:id/resolve

Resolve an alarm.

#### POST /alarms/:id/snooze

Snooze an alarm.

#### POST /alarms/:id/notes

Add note to alarm.

---

### Alarm Counts and Stats

#### GET /alarms/counts

Get alarm counts.

#### GET /alarms/stats

Get alarm statistics.

---

### Alarm Subscriptions

#### GET /alarms/subscriptions

Get user's alarm subscriptions.

#### PUT /alarms/subscriptions

Update alarm subscription.

---

### Bulk Actions

#### POST /alarms/bulk/acknowledge

Bulk acknowledge alarms.

#### POST /alarms/bulk/resolve

Bulk resolve alarms.

---

### Admin Alarm Actions

#### POST /alarms/admin/trigger

Manually trigger an alarm.

#### POST /alarms/admin/run-checks

Run alarm checks.

---

## App Logging (Industrial-Grade)

### Receive Batch Logs

#### POST /logs/batch

Receive batch logs from Flutter app.

---

### View Logs

#### GET /logs

Get application logs (role-based access).

#### GET /logs/sessions

Get log sessions.

#### GET /logs/stats

Get log statistics.

#### GET /logs/network

Get network request logs.

#### GET /logs/users

Get viewable users for log filtering (role-based).

---

### Cleanup

#### DELETE /logs/cleanup

Cleanup old logs (super admin only).

---

## Financial Reports

### Expense Summary

#### GET /reports/expense-summary

Get expense summary report.

---

### Vendor Aging

#### GET /reports/vendor-aging

Get vendor aging report.

---

### Cash Flow

#### GET /reports/cash-flow

Get cash flow report.

---

### Profit & Loss

#### GET /reports/profit-loss

Get profit and loss report.

---

### Balance Sheet

#### GET /reports/balance-sheet

Get balance sheet report.

---

## Error Codes

| Code | Description |
|------|-------------|
| COLLECTION_DEADLINE_MISSED | Collection deadline has passed |
| COLLECTION_ALREADY_RECORDED | Collection already recorded |
| VENDOR_NOT_FOUND | Vendor not found |
| EXPENSE_NOT_FOUND | Expense not found |
| INSUFFICIENT_BALANCE | Not enough balance for operation |
| BANK_ACCOUNT_NOT_FOUND | Bank account not found |
| RECONCILIATION_NOT_FOUND | Reconciliation record not found |
| ALREADY_APPROVED | Item already approved |
| ALREADY_REJECTED | Item already rejected |
| INVALID_AMOUNT | Amount must be positive |
| AUDIT_IN_PROGRESS | Cannot modify during active audit |
| ALARM_NOT_FOUND | Alarm not found |
| INVESTIGATION_NOT_FOUND | Investigation not found |

---

## Role Requirements Summary

| Endpoint | Roles Allowed |
|----------|---------------|
| View Finance Data | All authenticated users |
| Create/Update Expenses | salesman, manager, admin |
| Expense Categories | manager, admin |
| Money Collections | assistant_manager, manager, admin |
| Cash Management Admin | admin, owner |
| Bank Account Management | varies by operation |
| Reconciliations | manager, admin |
| Stock Verification | varies by operation |
| Executive Finance | salesman, executive, manager, admin |
| Tips Management | varies by operation |
| Detection Alerts | manager, admin |
| Investigations | admin |
| Audit Management | admin |
| Notifications | All authenticated users |
| Finance Matrix | manager, admin |
| Dashboard Metrics | assistant_manager, manager, admin |
| Alarm System | varies by operation |
| App Logging Admin | super admin |

# Implementation Checklist

Use this checklist to track progress on each module, sub-module, and micro-module.

---

## Legend

- [ ] Not started
- [~] In progress
- [x] Completed
- [!] Blocked/Issue

---

## Phase 1: Foundation (Weeks 1-4)

### 1. Core Module

#### 1.1 Database Sub-module
- [ ] Connection Pool (`database/postgres.go`)
- [ ] Query Builder (`database/query.go`)
- [ ] Transaction Manager (`database/transaction.go`)
- [ ] Migration Runner (`database/migrations/`)
- [ ] Unit Tests
- [ ] Integration Tests

#### 1.2 Cache Sub-module
- [ ] Redis Client (`cache/redis.go`)
- [ ] Cache Strategy (`cache/strategy.go`)
- [ ] Distributed Lock (`cache/lock.go`)
- [ ] Session Store (`cache/session.go`)
- [ ] Unit Tests

#### 1.3 Logger Sub-module
- [ ] Structured Logger (`logger/logger.go`)
- [ ] Request Logger (`logger/request.go`)
- [ ] Audit Logger (`logger/audit.go`)
- [ ] Error Tracker (`logger/error.go`)

#### 1.4 Config Sub-module
- [ ] Env Loader (`config/env.go`)
- [ ] Validator (`config/validator.go`)
- [ ] Feature Flags (`config/features.go`)
- [ ] Secrets Manager (`config/secrets.go`)

---

### 2. Auth Module

#### 2.1 Registration Sub-module
- [ ] Phone Registration (`auth/register_phone.go`)
- [ ] Email Registration (`auth/register_email.go`)
- [ ] Tenant Creation (`auth/register_tenant.go`)
- [ ] Validation (`auth/validation.go`)
- [ ] API: `POST /auth/register`
- [ ] Unit Tests
- [ ] Integration Tests

#### 2.2 OTP Sub-module
- [ ] OTP Generator - 6-digit, crypto/rand (`auth/otp/generator.go`)
- [ ] OTP Storage - SHA-256 hash, Redis (`auth/otp/storage.go`)
- [ ] OTP Verification - 3 attempts max (`auth/otp/verify.go`)
- [ ] OTP Delivery - SMS/WhatsApp (`auth/otp/delivery.go`)
- [ ] Rate Limiting - 1 per minute
- [ ] 10-minute expiry
- [ ] Unit Tests
- [ ] Integration Tests

#### 2.3 Token Sub-module
- [ ] JWT Generator - HS256 (`auth/token/jwt.go`)
- [ ] Token Validator (`auth/token/validator.go`)
- [ ] Token Refresh - rotation (`auth/token/refresh.go`)
- [ ] Token Blacklist (`auth/token/blacklist.go`)
- [ ] Access Token TTL: 15 min
- [ ] Refresh Token TTL: 7 days
- [ ] API: `POST /auth/refresh`
- [ ] Unit Tests

#### 2.4 Session Sub-module
- [ ] Session Manager (`auth/session/manager.go`)
- [ ] Device Tracker (`auth/session/device.go`)
- [ ] Concurrent Limit - 2 max (`auth/session/limit.go`)
- [ ] Session Events (`auth/session/events.go`)
- [ ] API: `GET /auth/sessions`
- [ ] API: `DELETE /auth/sessions/:id`
- [ ] API: `POST /auth/logout`
- [ ] API: `POST /auth/logout-all`
- [ ] Unit Tests

#### 2.5 Authorization Sub-module
- [ ] RBAC Engine (`auth/rbac/engine.go`)
- [ ] Permission Checker (`auth/rbac/permissions.go`)
- [ ] Role Hierarchy - 6 levels (`auth/rbac/hierarchy.go`)
- [ ] Middleware (`auth/rbac/middleware.go`)
- [ ] Unit Tests

---

### 3. Tenant Module

#### 3.1 Tenant Management Sub-module
- [ ] Tenant CRUD (`tenant/crud.go`)
- [ ] Tenant Isolation (`tenant/isolation.go`)
- [ ] Tenant Context (`tenant/context.go`)
- [ ] Subscription (`tenant/subscription.go`)
- [ ] API: `GET /tenants/:id`
- [ ] API: `PUT /tenants/:id`

#### 3.2 Settings Sub-module
- [ ] General Settings (`tenant/settings/general.go`)
- [ ] Business Rules (`tenant/settings/rules.go`)
- [ ] Feature Toggles (`tenant/settings/features.go`)
- [ ] Limits (`tenant/settings/limits.go`)
- [ ] `MoneyCollectionDeadlineMinutes` setting
- [ ] API: `GET /settings`
- [ ] API: `PUT /settings`

#### 3.3 Shop Sub-module
- [ ] Shop CRUD (`tenant/shop/crud.go`)
- [ ] Shop Assignment (`tenant/shop/assignment.go`)
- [ ] Shop Hours (`tenant/shop/hours.go`)
- [ ] Shop Location (`tenant/shop/location.go`)
- [ ] API: CRUD `/shops`

#### 3.4 User Management Sub-module
- [ ] User CRUD (`tenant/user/crud.go`)
- [ ] Role Assignment (`tenant/user/roles.go`)
- [ ] User Status (`tenant/user/status.go`)
- [ ] User Import (`tenant/user/import.go`)
- [ ] API: CRUD `/users`

---

## Phase 2: Core Business (Weeks 5-12)

### 4. Sales Module

#### 4.1 Draft Sub-module
- [ ] Draft CRUD (`sales/draft/crud.go`)
- [ ] Auto-save - 30 sec (`sales/draft/autosave.go`)
- [ ] Draft Recovery (`sales/draft/recovery.go`)
- [ ] Draft Validation (`sales/draft/validation.go`)
- [ ] API: `GET /daily-sales/draft`
- [ ] API: `PUT /daily-sales/draft`
- [ ] API: `DELETE /daily-sales/draft/:id`
- [ ] Unique constraint: (user_id, shop_id, record_date)
- [ ] Unit Tests
- [ ] Integration Tests

#### 4.2 Daily Sales Record Sub-module
- [ ] Record Creation (`sales/record/create.go`)
- [ ] Record Query (`sales/record/query.go`)
- [ ] Record Export (`sales/record/export.go`)
- [ ] Record Copy (`sales/record/copy.go`)
- [ ] API: `POST /daily-sales/draft/submit`
- [ ] API: `GET /daily-records`
- [ ] API: `GET /daily-records/:id`
- [ ] API: `POST /daily-records/:id/copy`
- [ ] Delete draft after submission
- [ ] Unique constraint: (shop_id, record_date)
- [ ] Unit Tests
- [ ] Integration Tests

#### 4.3 Sales Item Sub-module
- [ ] Item CRUD (`sales/item/crud.go`)
- [ ] Payment Split (`sales/item/payment.go`)
- [ ] Price Calculation (`sales/item/pricing.go`)
- [ ] Stock Tracking (`sales/item/stock.go`)
- [ ] Payment validation (sum = total)
- [ ] Unit Tests

#### 4.4 Approval Sub-module
- [ ] Approval Queue (`sales/approval/queue.go`)
- [ ] Approve Action (`sales/approval/approve.go`)
- [ ] Reject Action (`sales/approval/reject.go`)
- [ ] Bulk Approve (`sales/approval/bulk.go`)
- [ ] API: `POST /daily-records/:id/approve`
- [ ] API: `POST /daily-records/:id/reject`
- [ ] Stock deduction on approval
- [ ] Money collection creation on approval
- [ ] Notification on approval/rejection
- [ ] Unit Tests
- [ ] Integration Tests

#### 4.5 Return Sub-module
- [ ] Return Creation (`sales/return/create.go`)
- [ ] Return Approval (`sales/return/approval.go`)
- [ ] Stock Restoration (`sales/return/stock.go`)
- [ ] Refund Processing (`sales/return/refund.go`)
- [ ] API: `POST /sales/returns`
- [ ] API: `POST /sales/returns/:id/approve`

#### 4.6 Revert Sub-module
- [ ] Revert Action (`sales/revert/revert.go`)
- [ ] Stock Restoration on Revert
- [ ] Cancel Money Collection on Revert
- [ ] API: `POST /daily-records/:id/revert`
- [ ] Admin only permission
- [ ] Audit logging

---

### 5. Inventory Module

#### 5.1 Product Sub-module
- [ ] Product CRUD (`inventory/product/crud.go`)
- [ ] Product Import (`inventory/product/import.go`)
- [ ] Product Search (`inventory/product/search.go`)
- [ ] Product Validation (`inventory/product/validation.go`)
- [ ] API: CRUD `/products`
- [ ] API: `POST /products/import`
- [ ] API: `GET /products/search`
- [ ] SKU uniqueness
- [ ] Barcode uniqueness
- [ ] Unit Tests

#### 5.2 Category Sub-module
- [ ] Category CRUD (`inventory/category/crud.go`)
- [ ] Sub-category (`inventory/category/subcategory.go`)
- [ ] Category Rules (`inventory/category/rules.go`)
- [ ] API: CRUD `/categories`
- [ ] API: CRUD `/subcategories`

#### 5.3 Stock Sub-module
- [ ] Stock Query (`inventory/stock/query.go`)
- [ ] Stock Update (`inventory/stock/update.go`)
- [ ] Stock Movement (`inventory/stock/movement.go`)
- [ ] Low Stock Alert (`inventory/stock/alerts.go`)
- [ ] API: `GET /stocks`
- [ ] API: `GET /stocks/product/:id`
- [ ] API: `POST /stocks/adjust`
- [ ] Movement tracking for all changes
- [ ] Negative stock validation
- [ ] Unit Tests
- [ ] Integration Tests

#### 5.4 Purchase Sub-module
- [ ] Purchase Draft (`inventory/purchase/draft.go`)
- [ ] Purchase Order (`inventory/purchase/order.go`)
- [ ] PO Approval (`inventory/purchase/approval.go`)
- [ ] Goods Receipt (`inventory/purchase/receipt.go`)
- [ ] API: CRUD `/purchases`
- [ ] API: `POST /purchases/:id/approve`
- [ ] API: `POST /purchases/:id/receive`
- [ ] Stock addition on receipt
- [ ] Vendor ledger update
- [ ] Unit Tests

#### 5.5 Transfer Sub-module
- [ ] Transfer Request (`inventory/transfer/request.go`)
- [ ] Transfer Approval (`inventory/transfer/approval.go`)
- [ ] Transfer Receipt (`inventory/transfer/receipt.go`)
- [ ] Transfer Tracking (`inventory/transfer/tracking.go`)
- [ ] API: `POST /stocks/transfer`
- [ ] API: `POST /transfers/:id/approve`
- [ ] API: `POST /transfers/:id/receive`
- [ ] Stock reservation
- [ ] Two-shop approval
- [ ] Unit Tests
- [ ] Integration Tests

---

### 6. Finance Module

#### 6.1 Money Collection Sub-module (CRITICAL!)
- [ ] Collection Creation (`finance/collection/create.go`)
- [ ] Collection Recording (`finance/collection/record.go`)
- [ ] Deadline Tracking (`finance/collection/deadline.go`)
- [ ] Overdue Handling (`finance/collection/overdue.go`)
- [ ] Reassignment (`finance/collection/reassign.go`)
- [ ] API: `GET /money-collections`
- [ ] API: `GET /money-collections/:id`
- [ ] API: `POST /money-collections/:id/collect`
- [ ] API: `POST /money-collections/:id/approve`
- [ ] API: `POST /money-collections/:id/reassign`
- [ ] API: `GET /money-collections/overdue`
- [ ] Auto-creation on sales approval
- [ ] Configurable deadline (TenantSettings)
- [ ] Background job for deadline check
- [ ] Warning notification
- [ ] Escalation notification
- [ ] Unit Tests
- [ ] Integration Tests

#### 6.2 Cash Management Sub-module
- [ ] Cash Balance (`finance/cash/balance.go`)
- [ ] Cash Holdings (`finance/cash/holdings.go`)
- [ ] Cash Transactions (`finance/cash/transactions.go`)
- [ ] Cash Transfer (`finance/cash/transfer.go`)
- [ ] API: `GET /cash/balance`
- [ ] API: `POST /cash/holdings`
- [ ] API: `GET /cash/transactions`
- [ ] Denomination tracking
- [ ] Balance calculation
- [ ] Unit Tests

#### 6.3 Expense Sub-module
- [ ] Expense CRUD (`finance/expense/crud.go`)
- [ ] Expense Categories (`finance/expense/categories.go`)
- [ ] Expense Approval (`finance/expense/approval.go`)
- [ ] Receipt Upload (`finance/expense/receipts.go`)
- [ ] API: CRUD `/expenses`
- [ ] API: `POST /expenses/:id/approve`
- [ ] API: `POST /expenses/:id/reject`
- [ ] API: CRUD `/expense-headers`

#### 6.4 Vendor Sub-module
- [ ] Vendor CRUD (`finance/vendor/crud.go`)
- [ ] Vendor Ledger (`finance/vendor/ledger.go`)
- [ ] Vendor Payment (`finance/vendor/payment.go`)
- [ ] Vendor Balance (`finance/vendor/balance.go`)
- [ ] API: CRUD `/vendors`
- [ ] API: `GET /vendors/:id/ledger`
- [ ] API: `POST /vendors/:id/payments`

#### 6.5 Bank Account Sub-module
- [ ] Account CRUD (`finance/bank/crud.go`)
- [ ] Deposit Recording (`finance/bank/deposit.go`)
- [ ] Transaction History (`finance/bank/transactions.go`)
- [ ] API: CRUD `/bank-accounts`
- [ ] API: `POST /bank-accounts/:id/deposit`
- [ ] API: `GET /bank-accounts/:id/transactions`

#### 6.6 Reconciliation Sub-module
- [ ] Daily Reconciliation (`finance/recon/daily.go`)
- [ ] Variance Tracking (`finance/recon/variance.go`)
- [ ] Reconciliation Approval (`finance/recon/approval.go`)
- [ ] API: CRUD `/reconciliations`
- [ ] API: `POST /reconciliations/:id/complete`
- [ ] API: `POST /reconciliations/:id/approve`

---

## Phase 3: Advanced Features (Weeks 13-20)

### 7. OCR Module

#### 7.1 Session Sub-module
- [ ] Session Creation (`ocr/session/create.go`)
- [ ] Session Status (`ocr/session/status.go`)
- [ ] Session Results (`ocr/session/results.go`)
- [ ] API: `POST /ocr/sessions`
- [ ] API: `GET /ocr/sessions/:id`

#### 7.2 Image Processing Sub-module
- [ ] Image Upload (`ocr/image/upload.go`)
- [ ] Image Preprocessing (`ocr/image/preprocess.go`)
- [ ] Text Extraction (`ocr/image/extract.go`)
- [ ] S3 integration

#### 7.3 Data Extraction Sub-module
- [ ] Parser (`ocr/data/parser.go`)
- [ ] Product Matching (`ocr/data/matching.go`)
- [ ] Confidence Scoring (`ocr/data/confidence.go`)

#### 7.4 Import Sub-module
- [ ] Validation (`ocr/import/validation.go`)
- [ ] Batch Import (`ocr/import/batch.go`)
- [ ] Learning Feedback (`ocr/import/learning.go`)
- [ ] API: `POST /ocr/batch/import`
- [ ] API: `POST /ocr/items/:id/validate`

---

### 8. Reporting Module

#### 8.1 Sales Reports
- [ ] Daily Summary (`reports/sales/daily.go`)
- [ ] Product Analysis (`reports/sales/product.go`)
- [ ] Trend Analysis (`reports/sales/trends.go`)
- [ ] API: `GET /reports/sales/daily`
- [ ] API: `GET /reports/sales/product`

#### 8.2 Inventory Reports
- [ ] Stock Report (`reports/inventory/stock.go`)
- [ ] Movement Report (`reports/inventory/movement.go`)
- [ ] Valuation (`reports/inventory/valuation.go`)

#### 8.3 Finance Reports
- [ ] Cash Report (`reports/finance/cash.go`)
- [ ] Expense Report (`reports/finance/expense.go`)
- [ ] Collection Report (`reports/finance/collection.go`)

#### 8.4 Export
- [ ] Excel Export (`reports/export/excel.go`)
- [ ] PDF Export (`reports/export/pdf.go`)

---

## Phase 4: Intelligence (Weeks 21-24)

### 9. Notification Module

#### 9.1 In-App
- [ ] Notification CRUD (`notification/inapp/crud.go`)
- [ ] Mark Read (`notification/inapp/read.go`)
- [ ] API: CRUD `/notifications`

#### 9.2 Push
- [ ] FCM Integration (`notification/push/fcm.go`)
- [ ] Token Management (`notification/push/tokens.go`)

#### 9.3 WhatsApp
- [ ] Template Management (`notification/whatsapp/templates.go`)
- [ ] Message Delivery (`notification/whatsapp/delivery.go`)
- [ ] API: `POST /notifications/whatsapp`

---

### 10. Detection Module

#### 10.1 Alerts
- [ ] Alert Generation (`detection/alert/generate.go`)
- [ ] Alert Management (`detection/alert/manage.go`)
- [ ] Alert Resolution (`detection/alert/resolve.go`)
- [ ] API: CRUD `/detection/alerts`

#### 10.2 Investigations
- [ ] Investigation CRUD (`detection/investigation/crud.go`)
- [ ] API: CRUD `/detection/investigations`

---

### 11. Audit Module

#### 11.1 Schedules
- [ ] Schedule CRUD (`audit/schedule/crud.go`)
- [ ] API: CRUD `/audit/schedules`

#### 11.2 Sessions
- [ ] Session CRUD (`audit/session/crud.go`)
- [ ] API: CRUD `/audit/sessions`

#### 11.3 Findings
- [ ] Finding CRUD (`audit/finding/crud.go`)
- [ ] API: CRUD `/audit/findings`

#### 11.4 Stock Verification
- [ ] Verification Session (`audit/stock/session.go`)
- [ ] Variance Calculation (`audit/stock/variance.go`)
- [ ] API: CRUD `/stock-verifications`

---

### 12. Collaboration Module (Google Docs-style)

#### 12.1 Document Access Control Sub-module
- [ ] Document Model (`collaboration/models/document.go`)
- [ ] DocumentShare Model (`collaboration/models/share.go`)
- [ ] Permission Levels (view, comment, edit, admin)
- [ ] Share Types (private, team, org, public)
- [ ] Access Control Service (`collaboration/access/control.go`)
- [ ] Share Link Generation
- [ ] API: `POST /documents/{id}/share`
- [ ] API: `GET /documents/{id}/collaborators`
- [ ] Unit Tests

#### 12.2 WebSocket Authentication Sub-module
- [ ] JWT Token Validation for WS (`collaboration/auth/ws_auth.go`)
- [ ] Session Creation (`collaboration/auth/session.go`)
- [ ] Token Refresh via WS (`collaboration/auth/refresh.go`)
- [ ] Connection State Management
- [ ] Blacklist Checking
- [ ] Unit Tests

#### 12.3 Real-Time Sync Sub-module (CRDT/Yjs)
- [ ] Yjs Document Integration (`collaboration/sync/ydoc.go`)
- [ ] WebSocket Server (`collaboration/sync/ws_server.go`)
- [ ] Collaboration Room Management (`collaboration/sync/room.go`)
- [ ] Update Broadcasting (`collaboration/sync/broadcast.go`)
- [ ] Conflict Resolution (CRDT)
- [ ] Unit Tests
- [ ] Integration Tests

#### 12.4 Document Persistence Sub-module
- [ ] Content Storage Model (`collaboration/persist/content.go`)
- [ ] Version History Model (`collaboration/persist/version.go`)
- [ ] Debounced Auto-save (`collaboration/persist/autosave.go`)
- [ ] Version Snapshots (`collaboration/persist/snapshot.go`)
- [ ] Version Restore (`collaboration/persist/restore.go`)
- [ ] API: `GET /documents/{id}/versions`
- [ ] API: `POST /documents/{id}/versions/{vid}/restore`
- [ ] Unit Tests

#### 12.5 Comments Sub-module
- [ ] Comment Model with Threading (`collaboration/comments/model.go`)
- [ ] Anchor/Position Tracking (`collaboration/comments/anchor.go`)
- [ ] Comment Reactions (`collaboration/comments/reactions.go`)
- [ ] @Mentions with Notifications (`collaboration/comments/mentions.go`)
- [ ] Resolve/Reopen Comments (`collaboration/comments/resolve.go`)
- [ ] Comment Service (`collaboration/comments/service.go`)
- [ ] API: CRUD `/documents/{id}/comments`
- [ ] API: `POST /comments/{id}/resolve`
- [ ] API: `POST /comments/{id}/reactions`
- [ ] Real-time Comment Sync
- [ ] Unit Tests
- [ ] Integration Tests

#### 12.6 Presence & Awareness Sub-module
- [ ] Presence Tracker (`collaboration/presence/tracker.go`)
- [ ] Cursor Position Sync (`collaboration/presence/cursor.go`)
- [ ] Selection Highlight Sync (`collaboration/presence/selection.go`)
- [ ] User Color Assignment (`collaboration/presence/colors.go`)
- [ ] Active Users List (`collaboration/presence/users.go`)
- [ ] Heartbeat & Cleanup (`collaboration/presence/heartbeat.go`)
- [ ] API: `GET /documents/{id}/presence`
- [ ] Unit Tests

#### 12.7 Frontend Components
- [ ] CollaborativeEditor Component (TipTap + Yjs)
- [ ] CommentsPanel Component
- [ ] PresenceAvatars Component
- [ ] MentionInput Component
- [ ] ConnectionStatus Component
- [ ] DocumentToolbar Component
- [ ] VersionHistory Component
- [ ] ShareDialog Component
- [ ] CSS Styles (cursors, comments, presence)
- [ ] Keyboard Shortcuts
- [ ] Mobile Responsive Design
- [ ] Unit Tests (Jest/RTL)
- [ ] E2E Tests (Playwright)

---

## Progress Summary

| Module | Sub-modules | Completed | Progress |
|--------|-------------|-----------|----------|
| Core | 4 | 0 | 0% |
| Auth | 5 | 0 | 0% |
| Tenant | 4 | 0 | 0% |
| Sales | 6 | 0 | 0% |
| Inventory | 5 | 0 | 0% |
| Finance | 6 | 0 | 0% |
| OCR | 4 | 0 | 0% |
| Reporting | 4 | 0 | 0% |
| Notification | 3 | 0 | 0% |
| Detection | 2 | 0 | 0% |
| Audit | 4 | 0 | 0% |
| Collaboration | 7 | 0 | 0% |
| **Total** | **54** | **0** | **0%** |

---

## Notes

- Update this checklist as tasks are completed
- Mark items with [~] when in progress
- Mark items with [!] if blocked and add notes
- Each completed micro-module should have unit tests
- Integration tests should cover module interactions

# Technical Specification Document

## Document Information

| Field | Value |
|-------|-------|
| **Document ID** | SRS-001 |
| **Version** | 2.0.0 |
| **Classification** | Internal |
| **Last Updated** | January 2025 |
| **Status** | Approved |

---

## 1. Introduction

### 1.1 Purpose

This Software Requirements Specification (SRS) document describes the functional and non-functional requirements for the LiquorPro Liquor Shop Management Platform. It serves as the primary reference for technical implementation.

### 1.2 Scope

LiquorPro is a multi-tenant SaaS platform for liquor retail management, providing:

- Daily sales management and bulk entry
- Inventory and stock management
- Financial operations and vendor ledger
- AI-powered receipt OCR processing
- Real-time analytics and reporting
- Multi-shop management

### 1.3 Definitions & Acronyms

| Term | Definition |
|------|------------|
| **Tenant** | A distinct business entity (liquor shop owner/company) |
| **Shop** | A physical liquor retail location |
| **Daily Sales Record** | Aggregated sales for a shop on a specific day |
| **OCR** | Optical Character Recognition |
| **JWT** | JSON Web Token |
| **RBAC** | Role-Based Access Control |

---

## 2. System Overview

### 2.1 System Context

```
┌─────────────────────────────────────────────────────────────────┐
│                    LiquorPro Platform                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Mobile    │  │   Admin     │  │   Reports   │              │
│  │    App      │  │   Panel     │  │   Portal    │              │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
│         │                │                │                      │
│         └────────────────┼────────────────┘                      │
│                          ▼                                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    API Gateway                             │  │
│  └───────────────────────────────────────────────────────────┘  │
│         │          │          │          │          │           │
│         ▼          ▼          ▼          ▼          ▼           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐│
│  │   Auth   │ │  Sales   │ │Inventory │ │ Finance  │ │  SaaS  ││
│  │ Service  │ │ Service  │ │ Service  │ │ Service  │ │Service ││
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └────────┘│
│                          │                                       │
│                          ▼                                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │          PostgreSQL  │  Redis  │  Cloud Services          │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 User Classes

| User Class | Level | Description | Primary Functions |
|------------|-------|-------------|-------------------|
| **Owner** | 6 | Business owner/platform admin | Full control, tenant configuration |
| **Admin** | 5 | Tenant administrator | User management, system config |
| **Manager** | 4 | Shop manager | Approvals, reports, oversight |
| **Assistant Manager** | 3 | Support manager | Cash collection, limited approvals |
| **Executive** | 2 | Financial oversight | Financial reports, vendor management |
| **Salesman** | 1 | Shop floor staff | Daily sales entry, returns |

---

## 3. Functional Requirements

### 3.1 Authentication & Authorization

#### FR-AUTH-001: User Registration
- **Description**: New users can register with phone number and basic details
- **Inputs**: Phone, name, email (optional), tenant name (for admin)
- **Outputs**: User account created, OTP sent for verification
- **Business Rules**:
    - Phone number is indexed (not unique to allow re-registration)
    - OTP required for verification
    - Email validation if provided

#### FR-AUTH-002: OTP-Only Login
- **Description**: Users authenticate using phone + OTP only (no password)
- **Inputs**: Phone, OTP, device_info
- **Outputs**: JWT access token, refresh token
- **Business Rules**:
    - OTP valid for **10 minutes** (SHA-256 hashed in Redis)
    - **6-digit OTP**
    - Maximum **3 OTP verification attempts** per OTP
    - Maximum 2 concurrent device sessions

#### FR-AUTH-003: Session Management
- **Description**: Manage user sessions across devices
- **Inputs**: Session ID, user actions
- **Outputs**: Session status, device list
- **Business Rules**:
    - 2-device limit (Swiggy-style)
    - New login terminates oldest session if limit exceeded
    - Session expires after 24 hours of inactivity

#### FR-AUTH-004: Account Deletion
- **Description**: Users can request account deletion (App Store compliance)
- **Inputs**: User confirmation, reason (optional)
- **Outputs**: Account marked for deletion
- **Business Rules**:
    - 30-day grace period before permanent deletion
    - User can reactivate within grace period
    - Data anonymized after permanent deletion

### 3.2 Daily Sales Management

#### FR-SALES-001: Bulk Daily Sales Entry
- **Description**: Enter all daily sales in a single bulk grid interface
- **Inputs**: Date, shop, list of products with quantities and amounts
- **Outputs**: Daily sales record created
- **Business Rules**:
    - One record per shop per day
    - Cannot create record for future dates
    - Auto-calculate totals from line items
    - Save as draft until submitted

```
Bulk Entry Grid:
┌──────────────────┬──────────┬────────────┬───────────┬────────────┐
│ Product          │ Quantity │ Unit Price │ Discount  │ Total      │
├──────────────────┼──────────┼────────────┼───────────┼────────────┤
│ Royal Challenge  │ 10       │ 450.00     │ 0.00      │ 4,500.00   │
│ Blenders Pride   │ 5        │ 550.00     │ 50.00     │ 2,700.00   │
│ McDowell's No.1  │ 20       │ 320.00     │ 0.00      │ 6,400.00   │
├──────────────────┼──────────┼────────────┼───────────┼────────────┤
│ TOTAL            │ 35       │            │ 50.00     │ 13,600.00  │
└──────────────────┴──────────┴────────────┴───────────┴────────────┘
```

#### FR-SALES-002: Daily Sales Approval Workflow
- **Description**: Manager reviews and approves daily sales records
- **Inputs**: Record ID, approval decision, comments
- **Outputs**: Record status updated, notifications sent
- **Business Rules**:
    - Only managers can approve/reject
    - Rejected records return to salesman for correction
    - Approved records trigger finance reconciliation

```
Data Flow (Drafts in Separate Table):
┌─────────────────┐                    ┌────────────────────────────────┐
│ DailySalesDraft │     Submit         │    DailySalesRecord            │
│ (separate table)│ ───────────────►   │                                │
│                 │     (creates        │ ┌─────────┐    ┌──────────┐   │
│ - draft_data    │      new record)    │ │ Pending │───►│ Approved │   │
│ - auto-saved    │                     │ └────┬────┘    └──────────┘   │
└─────────────────┘                     │      │                        │
                                        │      │ Reject                 │
                                        │      ▼                        │
                                        │ ┌──────────┐                  │
                                        │ │ Rejected │ → Copy & Edit    │
                                        │ └──────────┘                  │
                                        └────────────────────────────────┘

Note: Drafts are stored in daily_sales_drafts table and deleted after submission.
The main daily_sales_records table only has statuses: pending, approved, rejected.
```

#### FR-SALES-003: Sales Return Processing
- **Description**: Process customer returns and refunds
- **Inputs**: Original sale ID, return items, reason
- **Outputs**: Return record, inventory adjustment
- **Business Rules**:
    - Returns only for approved sales
    - Must specify return reason
    - Stock automatically adjusted
    - Partial returns supported

### 3.3 OCR Receipt Processing

#### FR-OCR-001: Batch Image Upload
- **Description**: Upload multiple receipt images for OCR processing
- **Inputs**: Array of images (JPG/PNG), shop ID
- **Outputs**: Batch session ID, processing status
- **Business Rules**:
    - Maximum 200 images per batch
    - Maximum 10MB per image
    - Supported formats: JPG, PNG
    - Background processing with status updates

#### FR-OCR-002: AI-Powered Data Extraction
- **Description**: Extract structured data from receipt images using AI
- **Inputs**: OCR text from Cloud Vision
- **Outputs**: Structured data (brand, size, quantity, price, GST)
- **Business Rules**:
    - Match extracted brands to product catalog
    - Flag low-confidence extractions for review
    - Deduplicate entries
    - Calculate GST from amounts

#### FR-OCR-003: Manual Review Interface
- **Description**: Review and correct AI-extracted data
- **Inputs**: Extracted data, corrections
- **Outputs**: Validated sales records
- **Business Rules**:
    - Show original image alongside extracted data
    - Allow field-by-field correction
    - Track accuracy metrics for AI improvement

### 3.4 Inventory Management

#### FR-INV-001: Product Catalog Management
- **Description**: Maintain product master data
- **Inputs**: Product details (name, brand, category, price, SKU)
- **Outputs**: Product record
- **Business Rules**:
    - SKU unique within tenant
    - Price history maintained
    - Soft delete for inactive products

#### FR-INV-002: Stock Level Tracking
- **Description**: Track current stock levels per shop
- **Inputs**: Stock movements (purchase, sale, transfer, adjustment)
- **Outputs**: Current stock quantity, stock history
- **Business Rules**:
    - Costing method: FIFO, LIFO, or Average (configurable)
    - Track batch/lot numbers for expiry
    - Alert on low stock (below reorder level)

#### FR-INV-003: Purchase Order Workflow
- **Description**: Create and manage stock purchase orders
- **Inputs**: Vendor, products, quantities, expected date
- **Outputs**: Purchase order, approval status
- **Business Rules**:
    - Manager approval required above threshold
    - Match received goods against PO
    - Auto-update stock on receipt

#### FR-INV-004: Stock Transfer
- **Description**: Transfer stock between shops
- **Inputs**: Source shop, destination shop, products, quantities
- **Outputs**: Transfer record, stock adjustments
- **Business Rules**:
    - Approval required for transfers
    - Source stock validated before transfer
    - Audit trail maintained

### 3.5 Finance Management

#### FR-FIN-001: Vendor Ledger
- **Description**: Track all transactions with vendors
- **Inputs**: Purchases, payments, adjustments
- **Outputs**: Running balance, ledger statement
- **Business Rules**:
    - Automatic ledger updates from purchases
    - Payment recording with proof
    - Monthly reconciliation

#### FR-FIN-002: Money Collection (Configurable Deadline)
- **Description**: Assistant Manager collects cash within deadline
- **Inputs**: Collection amount, daily sales record ID
- **Outputs**: Collection record, approval status
- **Business Rules**:
    - Default **15-minute deadline** from sales approval (configurable via `TenantSettings.MoneyCollectionDeadlineMinutes`)
    - Automatic notification at warning mark
    - Escalation if deadline missed
    - Manager notified of deadline breach
    - Deadline is tenant-configurable, not hardcoded

```
Timeline (Default 15 minutes, configurable per tenant):
Sales Approved                    Deadline              Escalation
     │                               │                      │
     ├─────── Configured Time ───────┤───── Escalation ─────┤
     │                               │                      │
     └─► Notify AM ───► Warning ─────┴─► Alert Manager ─────┘
```

#### FR-FIN-003: Expense Management
- **Description**: Track and approve shop expenses
- **Inputs**: Expense type, amount, receipt, description
- **Outputs**: Expense record, approval status
- **Business Rules**:
    - Category-based expense tracking
    - Receipt upload required
    - Manager approval for expenses above limit
    - Monthly expense reports

#### FR-FIN-004: Bank Account Management
- **Description**: Track cash and bank balances
- **Inputs**: Deposits, withdrawals, transfers
- **Outputs**: Account balance, transaction history
- **Business Rules**:
    - Reconciliation with bank statements
    - Daily cash balance verification
    - Cash deposit tracking

### 3.6 Reporting & Analytics

#### FR-RPT-001: Daily Sales Register (Purcha Report)
- **Description**: Generate daily sales register PDF
- **Inputs**: Date range, shop, format options
- **Outputs**: PDF report
- **Business Rules**:
    - Include all approved sales for period
    - Show product-wise breakdown
    - Calculate taxes and totals

#### FR-RPT-002: Dashboard Analytics
- **Description**: Real-time shop performance dashboard
- **Inputs**: Date range, shop filter
- **Outputs**: KPIs, charts, trends
- **Metrics**:
    - Daily/Weekly/Monthly sales
    - Top-selling products
    - Sales by category
    - Pending approvals count
    - Stock alerts

---

## 4. Non-Functional Requirements

### 4.1 Performance Requirements

| Requirement ID | Description | Target |
|----------------|-------------|--------|
| NFR-PERF-001 | API response time (p95) | < 500ms |
| NFR-PERF-002 | Page load time | < 3 seconds |
| NFR-PERF-003 | Concurrent users | 1,000+ |
| NFR-PERF-004 | Daily transactions | 100,000+ |
| NFR-PERF-005 | OCR batch processing | < 15 min for 200 images |

### 4.2 Reliability Requirements

| Requirement ID | Description | Target |
|----------------|-------------|--------|
| NFR-REL-001 | System uptime | 99.9% |
| NFR-REL-002 | Recovery Time Objective (RTO) | 4 hours |
| NFR-REL-003 | Recovery Point Objective (RPO) | 1 hour |
| NFR-REL-004 | Data durability | 99.999999999% |

### 4.3 Security Requirements

| Requirement ID | Description | Implementation |
|----------------|-------------|----------------|
| NFR-SEC-001 | Data encryption in transit | TLS 1.3 |
| NFR-SEC-002 | Data encryption at rest | AES-256 |
| NFR-SEC-003 | Password storage | bcrypt (cost 12) |
| NFR-SEC-004 | Session management | JWT + Redis |
| NFR-SEC-005 | Multi-tenant isolation | Tenant ID filtering |
| NFR-SEC-006 | Rate limiting | Per-endpoint limits |
| NFR-SEC-007 | Audit logging | Complete action trail |

### 4.4 Scalability Requirements

| Requirement ID | Description | Target |
|----------------|-------------|--------|
| NFR-SCL-001 | Horizontal scaling | Auto-scale to 10+ instances |
| NFR-SCL-002 | Database scaling | Read replicas, partitioning |
| NFR-SCL-003 | Tenant growth | Support 1,000+ tenants |
| NFR-SCL-004 | Data retention | 7 years historical data |

### 4.5 Usability Requirements

| Requirement ID | Description | Target |
|----------------|-------------|--------|
| NFR-USB-001 | Mobile-first design | Responsive UI |
| NFR-USB-002 | Offline capability | Queue operations when offline |
| NFR-USB-003 | Language support | English, Hindi |
| NFR-USB-004 | Accessibility | WCAG 2.1 Level A |

### 4.6 Compatibility Requirements

| Requirement ID | Description | Target |
|----------------|-------------|--------|
| NFR-CMP-001 | Mobile platforms | iOS 13+, Android 8+ |
| NFR-CMP-002 | Browsers | Chrome, Safari, Firefox (last 2 versions) |
| NFR-CMP-003 | API versioning | Backward compatible for 12 months |

---

## 5. Interface Requirements

### 5.1 API Interface

- **Protocol**: REST over HTTPS
- **Format**: JSON
- **Authentication**: Bearer JWT tokens
- **Versioning**: URL path (`/api/v1/`, `/api/v2/`)
- **Documentation**: OpenAPI 3.0 specification

### 5.2 External Integrations

| System | Purpose | Protocol |
|--------|---------|----------|
| Google Cloud Vision | OCR processing | HTTPS/gRPC |
| Google Gemini AI | Smart data extraction | HTTPS |
| Firebase | Push notifications | HTTPS |
| Razorpay | Payment processing | HTTPS |
| SMS Gateway | OTP delivery | HTTPS |

### 5.3 WebSocket Interface

- **Purpose**: Real-time updates
- **Events**:
    - `sales.approved` - Daily sales approved
    - `stock.low` - Low stock alert
    - `deadline.approaching` - 15-minute deadline warning
    - `notification.new` - New notification

---

## 6. Data Requirements

### 6.1 Data Retention

| Data Type | Retention Period | Archive Location |
|-----------|------------------|------------------|
| Sales records | 7 years | S3 Glacier |
| Audit logs | 7 years | S3 Standard-IA |
| User sessions | 90 days | Delete |
| OCR images | 90 days | Delete |
| Reports | 2 years | S3 Standard |

### 6.2 Data Backup

| Type | Frequency | Retention |
|------|-----------|-----------|
| Full database backup | Daily | 30 days |
| Incremental backup | Every 6 hours | 7 days |
| Transaction logs | Continuous | 24 hours |

---

## 7. Constraints

### 7.1 Technical Constraints

- Must use Go for backend services
- PostgreSQL as primary database
- Redis for caching and sessions
- Docker for containerization
- Kubernetes for orchestration (production)

### 7.2 Business Constraints

- 15-minute money collection deadline is non-negotiable
- Daily sales must be editable until approved
- Audit trail required for all financial transactions
- App Store compliance for account deletion

---

## 8. Acceptance Criteria

### 8.1 Functional Acceptance

- [ ] All user roles can authenticate successfully
- [ ] Daily sales bulk entry completes in under 5 minutes
- [ ] OCR batch processing handles 200 images
- [ ] Approval workflow functions correctly
- [ ] 15-minute deadline enforced with notifications
- [ ] Reports generate in under 30 seconds

### 8.2 Performance Acceptance

- [ ] API p95 latency < 500ms under load
- [ ] System handles 1,000 concurrent users
- [ ] No data loss during failover
- [ ] 99.9% uptime over 30 days

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 2.0.0 | Jan 2025 | Product Team | Complete rewrite for v2 |
| 1.5.0 | Oct 2024 | Product Team | Added OCR requirements |
| 1.0.0 | Jul 2024 | Product Team | Initial release |

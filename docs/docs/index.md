# LiquorPro Documentation

<div align="center">
  <h2>Enterprise Liquor Shop Management Platform</h2>
  <p><strong>Version 2025.01</strong> | Multi-Tenant SaaS Solution</p>
</div>

---

## Welcome to LiquorPro

LiquorPro is an enterprise-grade, multi-tenant SaaS platform designed specifically for liquor shop management. Built with modern microservices architecture, it addresses critical pain points in daily liquor retail operations.

### Key Value Propositions

| Problem | LiquorPro Solution |
|---------|-------------------|
| 45-minute daily sales entry | Bulk grid entry - 5 minutes |
| Paper-based receipt tracking | AI-powered OCR processing |
| Manual stock reconciliation | Real-time inventory sync |
| Delayed money collection | 15-minute deadline enforcement |
| Multi-shop chaos | Centralized multi-tenant control |

---

## Quick Navigation

<div class="grid cards" markdown>

-   :material-server:{ .lg .middle } **System Architecture**

    ---

    Understand the microservices architecture, infrastructure design, and security model

    [:octicons-arrow-right-24: View Architecture](system/overview.md)

-   :material-code-braces:{ .lg .middle } **Software Specification**

    ---

    Technical specifications, database design, and API contracts

    [:octicons-arrow-right-24: Technical Docs](software/technical-spec.md)

-   :material-book-open:{ .lg .middle } **User Guide**

    ---

    Step-by-step instructions for all user roles and daily operations

    [:octicons-arrow-right-24: Get Started](user-guide/getting-started.md)

-   :material-package:{ .lg .middle } **Product Documentation**

    ---

    Features, roadmap, and release notes

    [:octicons-arrow-right-24: Product Info](product/overview.md)

-   :material-sitemap:{ .lg .middle } **Workflows**

    ---

    Business process flows and approval workflows

    [:octicons-arrow-right-24: View Workflows](workflows/sales-workflow.md)

-   :material-api:{ .lg .middle } **API Reference**

    ---

    Complete API documentation for developers

    [:octicons-arrow-right-24: API Docs](api-reference/auth-api.md)

</div>

---

## Platform Overview

### Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────┐
│                    Mobile App / Admin Panel                      │
│                        (Flutter / React)                         │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS
┌────────────────────────────▼────────────────────────────────────┐
│                     Nginx Load Balancer                          │
│                   (SSL Termination, Routing)                     │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                    API Gateway (Port 8090)                       │
│         Authentication | Rate Limiting | Request Routing         │
└──┬──────────┬──────────┬──────────┬──────────┬──────────┬───────┘
   │          │          │          │          │          │
   ▼          ▼          ▼          ▼          ▼          ▼
┌─────┐  ┌──────┐  ┌────────┐  ┌──────────┐  ┌────────┐  ┌───────┐
│Auth │  │Sales │  │Inventory│  │Finance   │  │SaaS    │  │WebSocket│
│8091 │  │8092  │  │8093     │  │8094      │  │8095    │  │  Hub   │
└─────┘  └──────┘  └────────┘  └──────────┘  └────────┘  └───────┘
   │          │          │          │          │
   └──────────┴──────────┴──────────┴──────────┴──────────┐
                                                          │
              ┌───────────────────────────────────────────┴────┐
              │                                                 │
         ┌────▼────┐                                     ┌──────▼───┐
         │PostgreSQL│                                    │  Redis   │
         │ Database │                                    │  Cache   │
         └──────────┘                                    └──────────┘
```

### Core Services

| Service | Port | Responsibility |
|---------|------|----------------|
| **API Gateway** | 8090 | Request routing, authentication proxy, rate limiting |
| **Auth Service** | 8091 | User authentication, JWT tokens, session management |
| **Sales Service** | 8092 | Daily sales, returns, OCR processing, dashboards |
| **Inventory Service** | 8093 | Products, stocks, purchases, brand management |
| **Finance Service** | 8094 | Vendors, bank accounts, expenses, cash handling |
| **SaaS Service** | 8095 | Brand catalog, tenant management |

---

## Technology Stack

### Backend
- **Language**: Go 1.24.0
- **Framework**: Gin Web Framework
- **ORM**: GORM v1.30.0
- **Authentication**: JWT (golang-jwt v5)

### Infrastructure
- **Database**: PostgreSQL 15+
- **Cache**: Redis 7+
- **Message Queue**: Kafka (optional)
- **Container**: Docker & Kubernetes

### AI/ML Integration
- **OCR**: Google Cloud Vision API
- **Smart Extraction**: Google Gemini AI
- **Use Case**: Receipt processing & data extraction

### Monitoring
- **Metrics**: Prometheus
- **Tracing**: Jaeger (OpenTracing)
- **Logging**: Structured JSON logs

---

## User Roles

LiquorPro implements a hierarchical role-based access control system:

| Role | Level | Capabilities |
|------|-------|--------------|
| **SaaS Admin** | 100 | Platform-wide administration |
| **Admin** | 90 | Tenant administration, all permissions |
| **Manager** | 70 | Shop management, approvals, reports |
| **Assistant Manager** | 50 | Cash collection, basic approvals |
| **Executive** | 30 | Financial operations, oversight |
| **Salesman** | 10 | Daily sales entry, basic operations |

---

## Quick Start

### For Shop Staff (Salesman)
1. Log in with phone + OTP
2. Navigate to **Daily Sales**
3. Enter all products sold in the bulk entry grid
4. Submit for manager approval

### For Managers
1. Review pending daily sales records
2. Approve or reject with comments
3. Monitor shop dashboard
4. Generate daily reports

### For Administrators
1. Configure shop settings
2. Manage users and permissions
3. Review financial reports
4. Monitor system health

---

## Support & Resources

- **Documentation**: You're here!
- **API Status**: [status.liquorpro.io](https://status.liquorpro.io)
- **Support Email**: support@liquorpro.io
- **Issue Tracker**: [GitHub Issues](https://github.com/liquorpro/liquorpro/issues)

---

<div align="center">
  <p><strong>LiquorPro</strong> - Streamlining Liquor Retail Operations</p>
  <p>Built with :material-heart: by the LiquorPro Team</p>
</div>

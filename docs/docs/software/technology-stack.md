# Technology Stack

## Document Information

| Field | Value |
|-------|-------|
| **Document ID** | TECH-STACK-001 |
| **Version** | 2.0.0 |
| **Last Updated** | January 2025 |

---

## 1. Technology Overview

LiquorPro is built on a modern, cloud-native technology stack optimized for performance, scalability, and maintainability.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Presentation Layer                        │
├─────────────────────────────────────────────────────────────────┤
│  Flutter (Mobile)  │  React (Admin)  │  Progressive Web App     │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                          API Layer                               │
├─────────────────────────────────────────────────────────────────┤
│              Nginx (Reverse Proxy, Load Balancer)               │
│              Go + Gin (Microservices)                           │
│              REST API + WebSocket                               │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                         Data Layer                               │
├─────────────────────────────────────────────────────────────────┤
│  PostgreSQL (Primary)  │  Redis (Cache)  │  Kafka (Queue)       │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                      Infrastructure Layer                        │
├─────────────────────────────────────────────────────────────────┤
│  Docker  │  Kubernetes  │  Prometheus  │  Grafana  │  Jaeger    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Backend Technologies

### 2.1 Go (Golang) 1.24.0

**Role**: Primary backend language

**Why Go?**
| Benefit | Description |
|---------|-------------|
| Performance | Compiled language with near-C performance |
| Concurrency | Native goroutines for handling thousands of connections |
| Simplicity | Clean syntax, fast learning curve |
| Binary Deployment | Single binary, no runtime dependencies |
| Strong Typing | Catch errors at compile time |

**Key Packages:**
```go
// go.mod dependencies
go 1.24.0

require (
    github.com/gin-gonic/gin v1.10.0      // Web framework
    gorm.io/gorm v1.30.0                   // ORM
    gorm.io/driver/postgres v1.5.9         // PostgreSQL driver
    github.com/redis/go-redis/v9 v9.7.0    // Redis client
    github.com/golang-jwt/jwt/v5 v5.2.1    // JWT authentication
    github.com/spf13/viper v1.19.0         // Configuration
    go.uber.org/zap v1.27.0                // Structured logging
)
```

### 2.2 Gin Web Framework

**Role**: HTTP router and middleware

**Features Used:**
- High-performance HTTP routing
- Middleware chains (auth, logging, CORS)
- Request binding and validation
- JSON serialization

**Example:**
```go
router := gin.New()
router.Use(middleware.Logger())
router.Use(middleware.Recovery())
router.Use(middleware.CORS())

api := router.Group("/api/v1")
{
    api.POST("/login", authHandler.Login)
    api.GET("/products", middleware.Auth(), productHandler.List)
}
```

### 2.3 GORM v1.30.0

**Role**: Object-Relational Mapping

**Features Used:**
- Auto-migration
- Preloading associations
- Soft deletes
- Hooks (BeforeCreate, AfterUpdate)
- Transaction management

**Example:**
```go
type Product struct {
    gorm.Model
    TenantID  uuid.UUID `gorm:"type:uuid;not null;index"`
    Name      string    `gorm:"size:255;not null"`
    SKU       string    `gorm:"size:100;uniqueIndex"`
    Price     float64   `gorm:"not null"`
    Category  Category  `gorm:"foreignKey:CategoryID"`
}

// Query with tenant isolation
db.Where("tenant_id = ?", tenantID).Find(&products)
```

---

## 3. Database Technologies

### 3.1 PostgreSQL 15+

**Role**: Primary relational database

**Why PostgreSQL?**
| Feature | Benefit |
|---------|---------|
| ACID Compliance | Data integrity for financial transactions |
| UUID Support | Distributed ID generation |
| JSONB | Flexible schema for metadata |
| Full-Text Search | Product search capability |
| Partitioning | Table partitioning for scale |
| Extensions | PostGIS, pg_trgm, etc. |

**Configuration:**
```ini
# Key settings
max_connections = 300
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 16MB
```

### 3.2 Redis 7+

**Role**: Caching, sessions, rate limiting

**Use Cases:**
| Use Case | Data Structure | TTL |
|----------|---------------|-----|
| User sessions | String/Hash | 24h |
| Rate limiting | Sorted Set | 1-15min |
| Query cache | String | 5min |
| Real-time counters | String | - |
| Pub/Sub events | Stream | - |

**Configuration:**
```conf
maxmemory 1gb
maxmemory-policy allkeys-lru
appendonly yes
```

### 3.3 Apache Kafka (Optional)

**Role**: Event streaming, async processing

**Topics:**
- `sales.daily-records` - Daily sales events
- `inventory.stock-changes` - Stock movements
- `notifications.workflow` - Workflow notifications
- `audit.logs` - Audit trail

---

## 4. AI/ML Integration

### 4.1 Google Cloud Vision API

**Role**: Receipt OCR processing

**Capabilities:**
- Text detection (DOCUMENT_TEXT_DETECTION)
- Handwriting recognition
- Multi-language support

**Integration:**
```go
import vision "cloud.google.com/go/vision/apiv1"

client, _ := vision.NewImageAnnotatorClient(ctx)
annotations, _ := client.DetectDocumentText(ctx, image, nil)
```

### 4.2 Google Gemini AI

**Role**: Smart data extraction from OCR text

**Capabilities:**
- Entity extraction (brand, quantity, price)
- Data validation
- Pattern matching

**Prompt Engineering:**
```
Extract the following from this receipt text:
- Brand name
- Size (ml)
- Quantity
- Unit price
- Total price
- GST amount

Return as JSON format.
```

---

## 5. Frontend Technologies

### 5.1 Flutter (Mobile App)

**Role**: Cross-platform mobile application

**Key Packages:**
```yaml
dependencies:
  flutter_bloc: ^8.1.0      # State management
  dio: ^5.0.0               # HTTP client
  hive: ^2.2.0              # Local storage
  firebase_messaging: ^14.0.0  # Push notifications
```

### 5.2 React (Admin Panel)

**Role**: Web-based admin interface

**Key Libraries:**
```json
{
  "dependencies": {
    "react": "^18.2.0",
    "react-router-dom": "^6.0.0",
    "axios": "^1.4.0",
    "tailwindcss": "^3.3.0",
    "recharts": "^2.7.0"
  }
}
```

---

## 6. Infrastructure Technologies

### 6.1 Docker

**Role**: Containerization

**Base Images:**
```dockerfile
# Go services
FROM golang:1.24-alpine AS builder
FROM alpine:3.19 AS runtime

# PostgreSQL
FROM postgres:15-alpine

# Redis
FROM redis:7-alpine
```

### 6.2 Docker Compose

**Role**: Multi-container orchestration

**Services:**
```yaml
version: '3.8'
services:
  gateway:
    build: ./Dockerfile.gateway
    ports: ["8090:8090"]
  auth:
    build: ./Dockerfile.auth
    ports: ["8091:8091"]
  postgres:
    image: postgres:15-alpine
  redis:
    image: redis:7-alpine
```

### 6.3 Kubernetes

**Role**: Container orchestration for production

**Components:**
- Deployments for each microservice
- Services for internal communication
- Ingress for external access
- ConfigMaps and Secrets
- HorizontalPodAutoscaler

### 6.4 Nginx

**Role**: Reverse proxy, load balancer, SSL termination

**Features:**
- SSL/TLS termination
- Rate limiting
- Gzip compression
- WebSocket support
- Static file serving

---

## 7. Monitoring & Observability

### 7.1 Prometheus

**Role**: Metrics collection and alerting

**Metrics Collected:**
- HTTP request duration
- Request count by status
- Database connection pool
- Redis operations
- Go runtime metrics

### 7.2 Grafana

**Role**: Metrics visualization

**Dashboards:**
- Service health overview
- Request latency distribution
- Error rate trends
- Resource utilization

### 7.3 Jaeger

**Role**: Distributed tracing

**Features:**
- Request tracing across services
- Latency analysis
- Dependency mapping

### 7.4 Loki

**Role**: Log aggregation

**Integration:**
- Structured JSON logs
- Label-based querying
- Grafana integration

---

## 8. Development Tools

### 8.1 Version Control

| Tool | Purpose |
|------|---------|
| Git | Source control |
| GitHub | Repository hosting |
| GitHub Actions | CI/CD pipelines |

### 8.2 Code Quality

| Tool | Purpose |
|------|---------|
| golangci-lint | Go linting |
| gofmt | Code formatting |
| go test | Unit testing |
| go vet | Static analysis |

### 8.3 API Documentation

| Tool | Purpose |
|------|---------|
| Swagger/OpenAPI | API specification |
| Postman | API testing |
| MkDocs | Documentation site |

---

## 9. Security Tools

### 9.1 Authentication

| Component | Technology |
|-----------|------------|
| Token Format | JWT (HS256) |
| Password Hashing | bcrypt (cost 12) |
| OTP Delivery | SMS Gateway |

### 9.2 SSL/TLS

| Component | Technology |
|-----------|------------|
| Certificates | Let's Encrypt |
| TLS Version | 1.2, 1.3 |
| Certificate Management | Certbot |

---

## 10. Dependency Management

### 10.1 Go Modules

```bash
# Initialize module
go mod init github.com/liquorpro/liquorpro

# Add dependency
go get github.com/gin-gonic/gin@v1.10.0

# Update dependencies
go mod tidy

# Verify dependencies
go mod verify
```

### 10.2 Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| gin-gonic/gin | v1.10.0 | Web framework |
| gorm.io/gorm | v1.30.0 | ORM |
| redis/go-redis | v9.7.0 | Redis client |
| golang-jwt/jwt | v5.2.1 | JWT tokens |
| spf13/viper | v1.19.0 | Configuration |
| google/uuid | v1.6.0 | UUID generation |
| sirupsen/logrus | v1.9.3 | Logging |
| prometheus/client | v1.23.2 | Metrics |

---

## 11. Technology Decisions

### 11.1 Why This Stack?

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Go over Node.js | Node.js, Python, Java | Performance, concurrency, binary deployment |
| PostgreSQL over MySQL | MySQL, MongoDB | ACID, UUID, JSONB, extensions |
| Redis over Memcached | Memcached | Data structures, persistence, pub/sub |
| Gin over Echo | Echo, Fiber, Chi | Performance, community, stability |
| GORM over sqlx | sqlx, ent | Ease of use, migrations, associations |

### 11.2 Trade-offs

| Trade-off | Benefit | Cost |
|-----------|---------|------|
| Microservices | Scalability, isolation | Complexity, latency |
| JWT Tokens | Stateless auth | Token size, revocation |
| PostgreSQL | Data integrity | Scaling complexity |
| Go | Performance | Smaller ecosystem than Node.js |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 2.0.0 | Jan 2025 | Engineering Team | Complete documentation |
| 1.0.0 | Jul 2024 | Engineering Team | Initial release |

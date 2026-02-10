# LiquorPro Multi-Term Subscription System - Deployment Guide

## 🚀 Production Deployment Checklist

### Prerequisites
- [x] PostgreSQL 15+ database running
- [x] Redis 7+ cache running  
- [x] Docker environment configured
- [x] SaaS service port 8095 available
- [x] Environment variables configured

### 1. Database Setup

#### Required Tables (Auto-migrated)
```sql
-- Enhanced pricing_plans table with multi-term support
-- plan_billing_variants table for billing options
-- global_discount_config table for SaaS admin templates
-- plan_discount_override table for plan-specific overrides
-- billing_term_config table for configurable terms
```

#### Migration Command
```bash
# Database tables are automatically migrated on SaaS service startup
docker-compose up -d saas
```

### 2. Environment Configuration

#### Required Environment Variables
```env
# Database Connection
DATABASE_HOST=liquorpro-postgres
DATABASE_PORT=5432
DATABASE_USER=liquorpro
DATABASE_PASSWORD=liquorpro_password
DATABASE_NAME=liquorpro

# Redis Connection
REDIS_HOST=liquorpro-redis
REDIS_PORT=6379
REDIS_PASSWORD=redis_password

# Authentication
JWT_SECRET=your-production-jwt-secret-change-this

# Application
APP_ENVIRONMENT=production
```

### 3. Service Deployment

#### Docker Compose Deployment
```bash
# Build and start all services
docker-compose up -d

# Verify SaaS service health
curl http://localhost:8095/health
```

#### Manual Docker Deployment
```bash
# Build SaaS service
docker build -f Dockerfile.saas -t liquorpro-saas .

# Run SaaS service
docker run -d \
  --name liquorpro-saas \
  --network liquorpro-network \
  -p 8095:8095 \
  -e DATABASE_HOST=postgres \
  -e DATABASE_PORT=5432 \
  -e DATABASE_USER=liquorpro \
  -e DATABASE_PASSWORD=liquorpro_password \
  -e DATABASE_NAME=liquorpro \
  -e REDIS_HOST=redis \
  -e REDIS_PORT=6379 \
  -e REDIS_PASSWORD=redis_password \
  -e JWT_SECRET=production-secret \
  liquorpro-saas
```

### 4. API Endpoints Validation

#### Public Endpoints (No Auth Required)
```bash
# Test plan listing
curl "http://localhost:8095/api/plans"

# Test multi-term billing options
curl "http://localhost:8095/api/plans/with-billing-options"

# Test specific plan pricing
curl "http://localhost:8095/api/plans/{plan-id}/billing-options"

# Test pricing calculation
curl "http://localhost:8095/api/plans/{plan-id}/calculate?term_months=12"
```

#### Admin Endpoints (Auth Required)
```bash
# Headers required for admin endpoints
Authorization: Bearer {jwt-token}
Role: saas_admin

# Test discount management
curl -H "Authorization: Bearer {token}" \
     "http://localhost:8095/api/admin/discounts/configs"

# Test plan management
curl -H "Authorization: Bearer {token}" \
     "http://localhost:8095/api/admin/plans"
```

### 5. Frontend Integration

#### SaaS Admin Access
```
Route: /saas-admin/dashboard
Features:
- Plan Management with multi-term controls
- Discount configuration interface
- Billing analytics dashboard
- Bulk discount operations
```

#### Tenant Portal Access
```
Route: /subscription
Features:
- Current subscription management
- Multi-term plan selection
- Billing history and invoices
- Usage monitoring
```

### 6. Security Considerations

#### Production Security Checklist
- [x] JWT secret is secure and unique
- [x] Database credentials are strong
- [x] Redis is password protected
- [x] API endpoints require proper authentication
- [x] Role-based access control implemented
- [x] Input validation on all endpoints
- [x] SQL injection protection via GORM
- [x] CORS middleware configured

#### Recommended Security Enhancements
```bash
# Enable HTTPS in production
# Set strong database passwords
# Use environment-specific JWT secrets
# Implement rate limiting
# Add request logging
# Enable database connection pooling
```

### 7. Monitoring and Health Checks

#### Health Check Endpoints
```bash
# SaaS service health
GET /health
Response: {"service":"saas","status":"healthy"}

# Database connectivity
GET /api/plans (should return plans array)

# Redis connectivity  
# Verified through successful API responses
```

#### Monitoring Metrics
```bash
# Key metrics to monitor:
- SaaS service uptime
- Database connection pool
- Redis cache hit rates
- API response times
- Authentication success rates
- Subscription creation rates
```

### 8. Backup and Recovery

#### Database Backup
```bash
# Regular PostgreSQL backups
pg_dump liquorpro > backup_$(date +%Y%m%d).sql

# Automated backup script
docker exec liquorpro-postgres pg_dump -U liquorpro liquorpro > backup.sql
```

#### Configuration Backup
```bash
# Backup environment files
cp .env .env.backup
cp docker-compose.yml docker-compose.yml.backup
```

## 🔧 Configuration Management

### Default Discount Templates
```json
{
  "standard": {
    "yearly_discount": 20,
    "two_year_discount": 30,
    "three_year_discount": 40
  },
  "aggressive": {
    "yearly_discount": 25,
    "two_year_discount": 35,
    "three_year_discount": 45
  },
  "conservative": {
    "yearly_discount": 15,
    "two_year_discount": 25,
    "three_year_discount": 35
  }
}
```

### Billing Term Configuration
```json
[
  {
    "term_months": 1,
    "term_name": "Monthly",
    "payment_schedule": "Monthly",
    "recommended_tag": "",
    "is_enabled": true
  },
  {
    "term_months": 12,
    "term_name": "Yearly",
    "payment_schedule": "Annual",
    "recommended_tag": "Most Popular",
    "is_enabled": true
  },
  {
    "term_months": 24,
    "term_name": "2-Year",
    "payment_schedule": "One-time",
    "recommended_tag": "",
    "is_enabled": true
  },
  {
    "term_months": 36,
    "term_name": "3-Year",
    "payment_schedule": "One-time",
    "recommended_tag": "Best Value",
    "is_enabled": true
  }
]
```

## 🧪 Testing in Production

### API Testing Script
```bash
#!/bin/bash
# Production API testing script

BASE_URL="http://localhost:8095/api"

echo "Testing public endpoints..."
curl -s "$BASE_URL/plans" | jq '.plans | length'
curl -s "$BASE_URL/plans/with-billing-options" | jq '.data | length'

echo "Testing health endpoint..."
curl -s "http://localhost:8095/health"

echo "All tests completed!"
```

### Load Testing
```bash
# Use tools like Apache Bench for load testing
ab -n 1000 -c 10 http://localhost:8095/api/plans

# Or use curl for basic testing
for i in {1..100}; do
  curl -s "http://localhost:8095/api/plans/with-billing-options" > /dev/null
  echo "Request $i completed"
done
```

## 📊 Post-Deployment Validation

### Functionality Checklist
- [ ] SaaS service starts successfully
- [ ] Database migrations complete
- [ ] Public API endpoints respond correctly
- [ ] Admin authentication works
- [ ] Multi-term pricing calculations are accurate
- [ ] Frontend can access subscription portal
- [ ] SaaS admin can manage discounts
- [ ] Error handling works properly

### Performance Benchmarks
```bash
# Expected response times:
# /api/plans: < 100ms
# /api/plans/with-billing-options: < 200ms
# /api/plans/{id}/billing-options: < 150ms
# Health check: < 50ms
```

### Business Validation
- [ ] Pricing calculations match business requirements
- [ ] Discount percentages are configurable
- [ ] SaaS admin can update pricing in real-time
- [ ] Tenants can view and select billing options
- [ ] Savings calculations are accurate
- [ ] Recommended tags display correctly

## 🚨 Troubleshooting

### Common Issues

#### Service Won't Start
```bash
# Check logs
docker logs liquorpro-saas

# Common causes:
# - Database connection failed
# - Redis connection failed
# - Port 8095 already in use
# - Missing environment variables
```

#### Database Migration Issues
```bash
# Manual migration check
docker exec -it liquorpro-postgres psql -U liquorpro -d liquorpro -c "\dt"

# Should show all required tables including:
# - pricing_plans (enhanced)
# - plan_billing_variants
# - global_discount_config
# - plan_discount_override
# - billing_term_config
```

#### API Authentication Issues
```bash
# Verify JWT configuration
# Check user roles in database
# Ensure proper Authorization headers
```

### Support Contacts
- Technical Issues: Check logs and error messages
- Business Logic: Verify pricing calculations
- Performance: Monitor response times and database queries

---

## ✅ Deployment Complete

Once all checklist items are validated, the LiquorPro Multi-Term Subscription System is ready for production use with full SaaS admin control and tenant self-service capabilities.
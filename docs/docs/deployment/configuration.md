# Configuration Guide

## Overview

This guide covers all configuration options for LiquorPro.

---

## 1. Configuration File

Create `config.yaml` in the root directory:

```yaml
# Application settings
app:
  name: LiquorPro
  version: 2025.01
  environment: production  # development, staging, production
  debug: false
  log_level: info  # debug, info, warn, error

# Server settings
server:
  host: 0.0.0.0
  port: 8090
  read_timeout: 30
  write_timeout: 30
  idle_timeout: 60

# Database settings
database:
  host: ${DATABASE_HOST}
  port: 5432
  user: ${DATABASE_USER}
  password: ${DATABASE_PASSWORD}
  dbname: liquorpro
  sslmode: disable
  timezone: Asia/Kolkata
  max_connections: 100
  max_idle_connections: 10
  connection_max_lifetime: 3600

# Redis settings
redis:
  host: ${REDIS_HOST}
  port: 6379
  password: ${REDIS_PASSWORD}
  db: 0
  pool_size: 10

# JWT settings
jwt:
  secret: ${JWT_SECRET}
  expiration_hours: 24
  refresh_hours: 168
  issuer: liquorpro

# Service ports
services:
  gateway:
    host: 0.0.0.0
    port: 8090
  auth:
    host: 0.0.0.0
    port: 8091
  sales:
    host: 0.0.0.0
    port: 8092
  inventory:
    host: 0.0.0.0
    port: 8093
  finance:
    host: 0.0.0.0
    port: 8094
  saas:
    host: 0.0.0.0
    port: 8095

# OCR settings
ocr:
  google_vision:
    enabled: true
    credentials_file: /config/firebase/service-account.json
  gemini:
    enabled: true
    api_key: ${GEMINI_API_KEY}
    model: gemini-pro

# Rate limiting
rate_limiting:
  enabled: true
  default_limit: 100
  default_window: 60
  login_limit: 5
  login_window: 900

# File upload
upload:
  max_size: 104857600  # 100MB
  allowed_types: ["image/jpeg", "image/png"]
  storage_path: /var/www/liquorpro/uploads

# Notifications
notifications:
  push:
    enabled: true
    firebase_credentials: /config/firebase/service-account.json
  sms:
    enabled: true
    provider: twilio
  email:
    enabled: true
    smtp_host: smtp.example.com
    smtp_port: 587
```

---

## 2. Environment Variables

Required environment variables:

```bash
# Database
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_USER=liquorpro
DATABASE_PASSWORD=secure_password
DATABASE_NAME=liquorpro

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=redis_password

# JWT
JWT_SECRET=your_256_bit_secret_key

# Google Cloud
GOOGLE_APPLICATION_CREDENTIALS=/config/firebase/service-account.json
GEMINI_API_KEY=your_gemini_api_key

# Application
APP_ENVIRONMENT=production
APP_DEBUG=false
```

---

## 3. Per-Environment Configuration

### Development
```yaml
app:
  environment: development
  debug: true
  log_level: debug

database:
  host: localhost
  sslmode: disable
```

### Staging
```yaml
app:
  environment: staging
  debug: false
  log_level: info

database:
  sslmode: prefer
```

### Production
```yaml
app:
  environment: production
  debug: false
  log_level: warn

database:
  sslmode: require
  max_connections: 300
```

---

## 4. Feature Flags

Enable/disable features:

```yaml
features:
  ocr_processing: true
  ai_validation: true
  websocket: true
  notifications: true
  rate_limiting: true
  audit_logging: true
```

---

## 5. Business Rules

Configure business rules:

```yaml
business_rules:
  cash_collection_deadline_minutes: 15
  max_backdate_days: 7
  max_devices_per_user: 2
  session_timeout_hours: 24
  otp_expiry_minutes: 5
  max_ocr_images_per_batch: 200
```

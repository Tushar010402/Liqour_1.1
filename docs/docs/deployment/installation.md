# Installation Guide

## Overview

This guide covers the installation and deployment of LiquorPro in various environments.

---

## 1. Prerequisites

### 1.1 System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 16 GB |
| Storage | 50 GB SSD | 200 GB SSD |
| OS | Ubuntu 20.04+ | Ubuntu 22.04 LTS |

### 1.2 Software Requirements

| Software | Version | Purpose |
|----------|---------|---------|
| Docker | 24.0+ | Containerization |
| Docker Compose | 2.20+ | Orchestration |
| Git | 2.30+ | Source control |
| Make | 4.0+ | Build automation |

### 1.3 Network Requirements

| Port | Service | Access |
|------|---------|--------|
| 80 | HTTP | Public |
| 443 | HTTPS | Public |
| 5432 | PostgreSQL | Internal |
| 6379 | Redis | Internal |
| 8090-8095 | Services | Internal |

---

## 2. Quick Start (Docker)

### 2.1 Clone Repository

```bash
git clone https://github.com/liquorpro/liquorpro.git
cd liquorpro
```

### 2.2 Environment Setup

```bash
# Copy example environment file
cp .env.example .env

# Edit environment variables
nano .env
```

**Required Environment Variables:**

```bash
# Database
DATABASE_HOST=postgres
DATABASE_PORT=5432
DATABASE_USER=liquorpro
DATABASE_PASSWORD=your_secure_password
DATABASE_NAME=liquorpro

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=your_redis_password

# JWT
JWT_SECRET=your_256_bit_secret_key
JWT_EXPIRATION_HOURS=24

# Application
APP_ENVIRONMENT=production
APP_DEBUG=false

# Google Cloud (for OCR)
GOOGLE_APPLICATION_CREDENTIALS=/config/firebase/service-account.json
```

### 2.3 Start Services

```bash
# Build and start all services
docker-compose up -d

# Check service status
docker-compose ps

# View logs
docker-compose logs -f
```

### 2.4 Run Migrations

```bash
# Run database migrations
docker-compose exec gateway ./migrate up

# Seed initial data (optional)
docker-compose exec gateway ./seed
```

### 2.5 Verify Installation

```bash
# Check health endpoint
curl http://localhost:8090/health

# Expected response
{"status": "healthy", "version": "2025.01"}
```

---

## 3. Production Deployment

### 3.1 Server Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Add user to docker group
sudo usermod -aG docker $USER
```

### 3.2 SSL Certificate Setup

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx -y

# Obtain certificate
sudo certbot certonly --nginx -d your-domain.com

# Auto-renewal is configured automatically
```

### 3.3 Production Docker Compose

```bash
# Use production compose file
docker-compose -f docker-compose.production.yml up -d
```

### 3.4 Nginx Configuration

```nginx
# /etc/nginx/sites-available/liquorpro
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location /api/ {
        proxy_pass http://127.0.0.1:8090;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /ws {
        proxy_pass http://127.0.0.1:8090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/liquorpro /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## 4. Kubernetes Deployment

### 4.1 Prerequisites

```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 4.2 Namespace Setup

```bash
kubectl create namespace liquorpro
kubectl config set-context --current --namespace=liquorpro
```

### 4.3 Secrets

```bash
# Create secrets
kubectl create secret generic liquorpro-secrets \
  --from-literal=database-password=your_db_password \
  --from-literal=redis-password=your_redis_password \
  --from-literal=jwt-secret=your_jwt_secret

# Create Google Cloud credentials
kubectl create secret generic google-credentials \
  --from-file=service-account.json=/path/to/service-account.json
```

### 4.4 Deploy

```bash
# Apply Kubernetes manifests
kubectl apply -f k8s/

# Or use Helm
helm install liquorpro ./helm/liquorpro -n liquorpro
```

### 4.5 Verify

```bash
# Check pods
kubectl get pods

# Check services
kubectl get services

# Check ingress
kubectl get ingress
```

---

## 5. Database Setup

### 5.1 PostgreSQL Initialization

```sql
-- Create database
CREATE DATABASE liquorpro;

-- Create user
CREATE USER liquorpro WITH ENCRYPTED PASSWORD 'your_password';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE liquorpro TO liquorpro;

-- Enable UUID extension
\c liquorpro
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### 5.2 Run Migrations

```bash
# Using make
make migrate-up

# Or directly
./cmd/migrate/migrate -direction up -config ./config.yaml
```

### 5.3 Seed Data

```bash
# Seed master brands
make seed-brands

# Seed test data (development only)
make seed-test
```

---

## 6. Configuration

### 6.1 Configuration File

Create `config.yaml`:

```yaml
database:
  host: localhost
  port: 5432
  user: liquorpro
  password: ${DATABASE_PASSWORD}
  dbname: liquorpro
  sslmode: disable
  timezone: Asia/Kolkata
  max_connections: 100
  max_idle_connections: 10

redis:
  host: localhost
  port: 6379
  password: ${REDIS_PASSWORD}
  db: 0

jwt:
  secret: ${JWT_SECRET}
  expiration_hours: 24
  refresh_hours: 168
  issuer: liquorpro

server:
  host: 0.0.0.0
  port: 8090
  read_timeout: 30
  write_timeout: 30
  idle_timeout: 60

app:
  name: LiquorPro
  version: 2025.01
  environment: production
  debug: false
  log_level: info

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

ocr:
  google_vision:
    enabled: true
    credentials_file: /config/firebase/service-account.json
  gemini:
    enabled: true
    api_key: ${GEMINI_API_KEY}

rate_limiting:
  enabled: true
  default_limit: 100
  default_window: 60
  login_limit: 5
  login_window: 900
```

---

## 7. Health Checks

### 7.1 Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/health` | Basic health check |
| `/health/ready` | Readiness check |
| `/health/live` | Liveness check |
| `/metrics` | Prometheus metrics |

### 7.2 Monitoring Setup

```bash
# Install Prometheus
docker run -d \
  --name prometheus \
  -p 9090:9090 \
  -v /path/to/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus

# Install Grafana
docker run -d \
  --name grafana \
  -p 3000:3000 \
  grafana/grafana
```

---

## 8. Backup Configuration

### 8.1 Automated Backups

```bash
# Create backup script
cat > /opt/scripts/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backups/postgres"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

docker exec liquorpro-db pg_dump -U liquorpro liquorpro | \
  gzip > "${BACKUP_DIR}/liquorpro_${TIMESTAMP}.sql.gz"

# Keep only last 30 days
find ${BACKUP_DIR} -name "*.sql.gz" -mtime +30 -delete
EOF

chmod +x /opt/scripts/backup.sh
```

### 8.2 Schedule Backups

```bash
# Add to crontab
crontab -e

# Add line:
0 2 * * * /opt/scripts/backup.sh
```

---

## 9. Troubleshooting

### 9.1 Common Issues

| Issue | Solution |
|-------|----------|
| Database connection failed | Check credentials and network |
| Redis connection refused | Verify Redis is running |
| Port already in use | Stop conflicting service |
| Permission denied | Check file permissions |

### 9.2 Logs

```bash
# View all logs
docker-compose logs -f

# View specific service
docker-compose logs -f gateway

# View last 100 lines
docker-compose logs --tail 100 gateway
```

### 9.3 Debug Mode

```bash
# Enable debug mode
APP_DEBUG=true docker-compose up
```

---

## 10. Next Steps

1. [Configure settings](configuration.md)
2. [Set up monitoring](monitoring.md)
3. [Configure backups](../system/infrastructure.md#backup-infrastructure)
4. [Review security](../system/security.md)

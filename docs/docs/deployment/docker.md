# Docker Deployment

## Overview

Deploy LiquorPro using Docker and Docker Compose.

---

## 1. Prerequisites

- Docker 24.0+
- Docker Compose 2.20+
- 4GB RAM minimum

---

## 2. Quick Start

```bash
# Clone repository
git clone https://github.com/liquorpro/liquorpro.git
cd liquorpro

# Copy environment file
cp .env.example .env

# Start services
docker-compose up -d

# Check status
docker-compose ps
```

---

## 3. Docker Compose Files

### Development
```bash
docker-compose -f docker-compose.dev.yml up -d
```

### Production
```bash
docker-compose -f docker-compose.production.yml up -d
```

---

## 4. Service Management

```bash
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# Restart specific service
docker-compose restart gateway

# View logs
docker-compose logs -f gateway

# Scale service
docker-compose up -d --scale sales=3
```

---

## 5. Building Images

```bash
# Build all images
docker-compose build

# Build specific service
docker-compose build gateway

# Build with no cache
docker-compose build --no-cache
```

---

## 6. Data Persistence

Volumes for persistent data:

```yaml
volumes:
  postgres_data:
  redis_data:
  uploads:
```

---

## 7. Networking

```yaml
networks:
  liquorpro-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.18.0.0/16
```

---

## 8. Health Checks

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8090/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

---

## 9. Troubleshooting

### Container won't start
```bash
docker-compose logs <service>
```

### Database connection issues
```bash
docker-compose exec postgres pg_isready
```

### Reset everything
```bash
docker-compose down -v
docker-compose up -d
```

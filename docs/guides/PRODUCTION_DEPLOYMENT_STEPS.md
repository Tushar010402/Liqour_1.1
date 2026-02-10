# 🚀 Production Deployment Steps for 72.60.96.174

## ✅ Prerequisites Checklist

- [x] Code pushed to GitHub
- [ ] SSH access to 72.60.96.174
- [ ] Domain name configured (pointing to 72.60.96.174)
- [ ] Root or sudo access on server

---

## Step 1: Initial Server Access (5 minutes)

### Connect to your server:

```bash
# Test connection
ssh root@72.60.96.174

# Or if you have a specific user:
ssh your_username@72.60.96.174
```

### Update the system:

```bash
apt-get update && apt-get upgrade -y
```

---

## Step 2: Clone Repository on Server (2 minutes)

```bash
# Install git if not present
apt-get install -y git

# Create project directory
mkdir -p /opt/liquorpro
cd /opt/liquorpro

# Clone your repository
# Replace YOUR_GITHUB_TOKEN with your actual token
git clone https://YOUR_GITHUB_TOKEN@github.com/Tushar010402/Liqour_1.1.git backend

# Or use SSH (recommended):
# git clone git@github.com:Tushar010402/Liqour_1.1.git backend

# Navigate to backend
cd backend
```

---

## Step 3: Run Initial Setup Script (10 minutes)

This script installs Docker, Nginx, and configures security:

```bash
cd /opt/liquorpro/backend

# Make scripts executable
chmod +x deployment/scripts/*.sh

# Run initial setup (installs everything)
sudo deployment/scripts/initial-setup.sh
```

**What this does:**
- ✅ Installs Docker & Docker Compose
- ✅ Installs Nginx
- ✅ Creates deploy user with proper permissions
- ✅ Configures SSH security (port 2222)
- ✅ Sets up firewall (UFW)
- ✅ Installs Fail2ban
- ✅ Creates backup directories

---

## Step 4: Configure Environment Variables (5 minutes)

```bash
cd /opt/liquorpro/backend

# Copy environment template
cp .env.example .env.production

# Generate secure passwords
echo "Database Password: $(openssl rand -base64 32)"
echo "Redis Password: $(openssl rand -base64 32)"
echo "JWT Secret: $(openssl rand -base64 64)"

# Edit .env.production with secure values
nano .env.production
```

**Required values:**
```env
# Database
DATABASE_HOST=postgres
DATABASE_PORT=5432
DATABASE_USER=liquorpro_prod
DATABASE_PASSWORD=<use_generated_password>
DATABASE_NAME=liquorpro_production

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=<use_generated_password>

# JWT
JWT_SECRET=<use_generated_secret>
JWT_EXPIRATION=24h

# Domain
DOMAIN_NAME=yourdomain.com

# Environment
APP_ENVIRONMENT=production
```

---

## Step 5: Configure Domain & SSL (10 minutes)

### Update Nginx configuration with your domain:

```bash
# Edit nginx config
nano deployment/nginx/sites-available/liquorpro.conf

# Replace 'yourdomain.com' with your actual domain
# Example: api.liquorpro.com
```

### Copy Nginx configs to system:

```bash
# Copy nginx configuration
sudo cp deployment/nginx/nginx.conf /etc/nginx/nginx.conf
sudo cp deployment/nginx/conf.d/* /etc/nginx/conf.d/
sudo cp deployment/nginx/sites-available/liquorpro.conf /etc/nginx/sites-available/

# Enable site
sudo ln -sf /etc/nginx/sites-available/liquorpro.conf /etc/nginx/sites-enabled/

# Test configuration (will fail initially - SSL certs don't exist yet)
sudo nginx -t
```

### Generate SSL certificate:

```bash
# Install certbot (if not already installed)
sudo apt-get install -y certbot python3-certbot-nginx

# Generate certificate (interactive)
sudo certbot --nginx -d yourdomain.com

# Follow prompts:
# - Enter email address
# - Agree to terms
# - Choose redirect option (2)

# Test automatic renewal
sudo certbot renew --dry-run
```

---

## Step 6: Deploy Backend Services (5 minutes)

```bash
cd /opt/liquorpro/backend

# First deployment
sudo deployment/scripts/deploy-production.sh v1.0.0
```

**What this does:**
- ✅ Creates database backup (if exists)
- ✅ Pulls latest code from Git
- ✅ Builds Docker images
- ✅ Runs database migrations
- ✅ Starts all services with zero downtime
- ✅ Runs health checks
- ✅ Auto-rollback on failure

**Expected output:**
```
🚀 LiquorPro Production Deployment - Version v1.0.0
========================================
Pre-Deployment Checks
========================================
✓ Pre-deployment checks passed
========================================
Building Docker Images
========================================
✓ Docker images built successfully
========================================
Starting Zero-Downtime Deployment
========================================
✓ Gateway is healthy
✓ Auth is healthy
✓ Sales is healthy
✓ Inventory is healthy
✓ Finance is healthy
✓ Frontend is healthy
========================================
✅ Deployment Successful!
========================================
```

---

## Step 7: Verify Deployment (2 minutes)

### Check service health:

```bash
# Run comprehensive health check
cd /opt/liquorpro/backend
sudo deployment/scripts/health-check-all.sh
```

### Test API endpoints:

```bash
# Test via Nginx (HTTPS)
curl https://yourdomain.com/gateway/health
curl https://yourdomain.com/auth/health
curl https://yourdomain.com/sales/health
curl https://yourdomain.com/inventory/health
curl https://yourdomain.com/finance/health

# Expected response: {"status":"healthy"}
```

### Check Docker containers:

```bash
docker ps
```

You should see 8 running containers:
- liquorpro-gateway-prod
- liquorpro-auth-prod
- liquorpro-sales-prod
- liquorpro-inventory-prod
- liquorpro-finance-prod
- liquorpro-frontend-prod
- liquorpro-postgres-prod
- liquorpro-redis-prod

---

## Step 8: Configure Monitoring (Optional, 5 minutes)

```bash
cd /opt/liquorpro/backend

# Start monitoring stack
docker-compose -f deployment/monitoring/docker-compose.monitoring.yml up -d

# Access Grafana
# URL: https://yourdomain.com/grafana
# Default login: admin / admin
```

---

## Step 9: Set Up Automated Backups (3 minutes)

```bash
# Add daily backup cron job
sudo crontab -e

# Add this line (runs backup at 2 AM daily):
0 2 * * * /opt/liquorpro/backend/deployment/scripts/backup-all.sh

# Test backup manually
sudo /opt/liquorpro/backend/deployment/scripts/backup-all.sh

# Check backup files
ls -lh /opt/liquorpro/backups/postgres/
```

---

## Step 10: Update Flutter App Configuration (2 minutes)

Update your Flutter app to point to production:

```dart
// lib/core/config/api_config.dart

class ApiConfig {
  // Change from localhost to your production domain
  static const String baseUrl = 'https://yourdomain.com';

  // All endpoints remain the same
  static const String gatewayUrl = '$baseUrl/gateway';
  static const String authUrl = '$baseUrl/auth';
  static const String salesUrl = '$baseUrl/sales';
  static const String inventoryUrl = '$baseUrl/inventory';
  static const String financeUrl = '$baseUrl/finance';
}
```

---

## 🎯 Complete Checklist

After completing all steps, verify:

- [ ] All 8 Docker containers running
- [ ] All health checks passing
- [ ] SSL certificate active (HTTPS working)
- [ ] Domain resolving to 72.60.96.174
- [ ] Nginx reverse proxy working
- [ ] Firewall configured (only ports 80, 443, 2222 open)
- [ ] Fail2ban active
- [ ] Automated backups scheduled
- [ ] Monitoring stack running (optional)
- [ ] Flutter app updated with production URL

---

## 🔧 Troubleshooting

### Services not starting:

```bash
# Check logs
docker-compose -f docker-compose.production.yml logs -f [service_name]

# Example
docker-compose -f docker-compose.production.yml logs -f gateway
```

### Database connection issues:

```bash
# Check PostgreSQL
docker exec liquorpro-postgres-prod pg_isready -U liquorpro_prod

# Check Redis
docker exec liquorpro-redis-prod redis-cli ping
```

### Nginx issues:

```bash
# Test configuration
sudo nginx -t

# Check error logs
sudo tail -f /opt/liquorpro/logs/nginx/error.log
```

### SSL certificate issues:

```bash
# Check certificate status
sudo certbot certificates

# Renew manually
sudo certbot renew --force-renewal
```

---

## 📚 Documentation References

- **Main Guide**: `deployment/README_DEPLOYMENT.md`
- **API Compatibility**: `deployment/docs/API_COMPATIBILITY_GUIDE.md`
- **Quick Start**: `deployment/docs/QUICK_START.md`
- **Troubleshooting**: `deployment/docs/TROUBLESHOOTING.md`
- **Integration Guide**: `deployment/INTEGRATION_GUIDE.md`

---

## 🆘 Support Commands

```bash
# View all services status
docker ps -a

# Restart all services
docker-compose -f docker-compose.production.yml restart

# Stop all services
docker-compose -f docker-compose.production.yml down

# View resource usage
docker stats

# Rollback to previous version
sudo deployment/scripts/rollback.sh
```

---

## 🎉 Success Criteria

Your deployment is successful when:

1. ✅ `curl https://yourdomain.com/gateway/health` returns `{"status":"healthy"}`
2. ✅ Flutter app can login and access all features
3. ✅ All health checks pass (90%+ pass rate)
4. ✅ SSL certificate is A+ rated (test at: https://www.ssllabs.com/ssltest/)
5. ✅ All Docker containers are in "Up" state
6. ✅ Backups are created successfully

---

**Server**: 72.60.96.174
**Repository**: https://github.com/Tushar010402/Liqour_1.1
**Deployment Date**: 2025-10-26

Ready to go live! 🚀

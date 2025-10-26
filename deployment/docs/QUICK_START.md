# LiquorPro Production - Quick Start Guide

## 🚀 5-Minute Quick Start

For experienced DevOps engineers who want to get up and running quickly.

### Server: 72.60.96.174

---

## Step 1: Initial Server Setup (90 seconds)

```bash
# SSH to server as root
ssh root@72.60.96.174

# Run setup script
curl -fsSL https://raw.githubusercontent.com/your-org/liquorpro/main/deployment/scripts/initial-setup.sh | bash

# Test new SSH connection (port 2222)
# In NEW terminal:
ssh -p 2222 deploy@72.60.96.174
```

---

## Step 2: SSL Certificate (60 seconds)

```bash
# Configure DNS first:
# A Record: yourdomain.com → 72.60.96.174

# Generate SSL
sudo certbot --nginx -d yourdomain.com -d api.yourdomain.com
```

---

## Step 3: Deploy Backend (3 minutes)

```bash
# Clone repo
cd /opt/liquorpro/backend
git clone https://github.com/your-org/liquorpro.git .

# Configure environment
cp .env.production.example .env.production

# Update critical values:
nano .env.production
# - DATABASE_PASSWORD (openssl rand -base64 32)
# - REDIS_PASSWORD (openssl rand -base64 32)
# - JWT_SECRET (openssl rand -base64 64)
# - DOMAIN_NAME=yourdomain.com

# Configure Nginx
sudo cp deployment/nginx/nginx.conf /etc/nginx/
sudo cp deployment/nginx/sites-available/liquorpro.conf /etc/nginx/sites-available/
sudo cp deployment/nginx/conf.d/*.conf /etc/nginx/conf.d/
sudo sed -i 's/yourdomain.com/YOURACTUAL.com/g' /etc/nginx/sites-available/liquorpro.conf
sudo ln -sf /etc/nginx/sites-available/liquorpro.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Deploy!
chmod +x deployment/scripts/*.sh
./deployment/scripts/deploy-production.sh v1.0.0
```

---

## Step 4: Verify (30 seconds)

```bash
# Health check
./deployment/scripts/health-check-all.sh

# Should show:
# ✅ System Status: HEALTHY
```

---

## Done! 🎉

Your production backend is now live at:
- **API**: https://yourdomain.com/gateway/health
- **Monitoring**: https://yourdomain.com/grafana

---

## Essential Commands

```bash
# Deploy update
./deployment/scripts/deploy-production.sh v1.0.x

# Rollback
./deployment/scripts/rollback.sh

# Check health
./deployment/scripts/health-check-all.sh

# Backup
./deployment/scripts/backup-all.sh

# View logs
docker-compose -f docker-compose.production.yml logs -f [service]
```

---

## Troubleshooting One-Liners

```bash
# All services status
docker-compose -f docker-compose.production.yml ps

# Restart all
docker-compose -f docker-compose.production.yml restart

# Check resource usage
docker stats

# Check Nginx
sudo nginx -t && sudo systemctl status nginx

# Database connection
docker exec -it liquorpro-postgres-prod psql -U liquorpro_prod -d liquorpro_production

# Redis connection
docker exec -it liquorpro-redis-prod redis-cli
```

---

## Next Steps

1. **Set up monitoring**: See `deployment/docs/MONITORING_GUIDE.md`
2. **Configure backups**: See `deployment/docs/BACKUP_GUIDE.md`
3. **Set up CI/CD**: See `deployment/docs/CICD_GUIDE.md`
4. **Security hardening**: See `deployment/docs/SECURITY_CHECKLIST.md`

---

## Need Help?

- Full guide: `deployment/docs/DEPLOYMENT_GUIDE.md`
- Troubleshooting: `deployment/docs/TROUBLESHOOTING.md`
- Architecture: `deployment/docs/ARCHITECTURE.md`

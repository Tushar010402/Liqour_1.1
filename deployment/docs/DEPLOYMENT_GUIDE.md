# LiquorPro Production Deployment Guide

## Server Information
- **IP Address**: 72.60.96.174
- **OS**: Ubuntu 22.04 LTS
- **SSH Port**: 2222 (custom for security)
- **Domain**: yourdomain.com (configure your DNS)

---

## Prerequisites

Before deployment, ensure you have:
- [ ] Domain name with DNS access
- [ ] SSH access to server (72.60.96.174)
- [ ] GitHub repository access
- [ ] SSL certificate email address
- [ ] Strong passwords ready (JWT secret, database, Redis)
- [ ] OCR API credentials (Google Vision, Gemini)
- [ ] S3/backup storage configured (optional)

---

## Step-by-Step Deployment

### Phase 1: Initial Server Setup (1-2 hours)

#### 1.1 Connect to Server

```bash
# Initial connection (default SSH port 22)
ssh root@72.60.96.174

# If that doesn't work, try:
ssh -p 22 root@72.60.96.174
```

#### 1.2 Run Initial Setup Script

```bash
# Upload and run the initial setup script
# On your local machine:
scp deployment/scripts/initial-setup.sh root@72.60.96.174:/tmp/

# On the server:
chmod +x /tmp/initial-setup.sh
/tmp/initial-setup.sh
```

This script will:
- Update system packages
- Install Docker, Docker Compose, Nginx
- Create `deploy` user with sudo access
- Configure SSH security (port 2222)
- Set up firewall (UFW)
- Configure Fail2ban
- Create directory structure
- Generate DH parameters for SSL

**IMPORTANT**: Before logging out, test the new SSH configuration:
```bash
# In a NEW terminal (don't close the root session yet):
ssh -p 2222 deploy@72.60.96.174
```

Only logout of root after confirming deploy user SSH works!

#### 1.3 Add SSH Key for Deploy User

```bash
# On your local machine, generate SSH key if you don't have one:
ssh-keygen -t rsa -b 4096 -f ~/.ssh/liquorpro_prod_rsa

# Copy public key to server:
ssh-copy-id -i ~/.ssh/liquorpro_prod_rsa.pub -p 2222 deploy@72.60.96.174

# Test connection:
ssh -p 2222 deploy@72.60.96.174
```

#### 1.4 Configure SSH Config (Optional but Recommended)

Add to `~/.ssh/config`:
```
Host liquorpro-prod
    HostName 72.60.96.174
    Port 2222
    User deploy
    IdentityFile ~/.ssh/liquorpro_prod_rsa
```

Now you can connect with: `ssh liquorpro-prod`

---

### Phase 2: DNS and SSL Configuration (30 minutes)

#### 2.1 Configure DNS

Point your domain to the server:
```
Type: A Record
Name: @ (or yourdomain.com)
Value: 72.60.96.174
TTL: 3600

Type: A Record
Name: api
Value: 72.60.96.174
TTL: 3600
```

Wait for DNS propagation (check with `dig yourdomain.com`)

#### 2.2 Generate SSL Certificate

```bash
# On the server as deploy user:
sudo certbot --nginx -d yourdomain.com -d api.yourdomain.com

# Follow the prompts and provide:
# - Email address for urgent renewal notices
# - Agree to Terms of Service
# - Choose to redirect HTTP to HTTPS (option 2)
```

The certificate will be auto-renewed. Test renewal:
```bash
sudo certbot renew --dry-run
```

---

### Phase 3: Deploy Backend Application (1-2 hours)

#### 3.1 Clone Repository

```bash
ssh liquorpro-prod

cd /opt/liquorpro/backend
git clone https://github.com/your-org/liquorpro.git .

# Or if using SSH:
git clone git@github.com:your-org/liquorpro.git .
```

#### 3.2 Configure Environment

```bash
# Copy environment template
cp .env.production .env.production.backup
cp .env.production.example .env.production

# Edit with your values
nano .env.production
```

**Critical values to update**:
```bash
# Generate JWT secret (min 64 characters):
openssl rand -base64 64

# Generate strong passwords:
openssl rand -base64 32

# Update in .env.production:
DATABASE_PASSWORD=<generated_password>
REDIS_PASSWORD=<generated_password>
JWT_SECRET=<generated_jwt_secret>
GEMINI_API_KEY=<your_gemini_key>
DOMAIN_NAME=yourdomain.com
SSL_EMAIL=admin@yourdomain.com
```

#### 3.3 Set Up Credentials

```bash
# Create credentials directory
mkdir -p /opt/liquorpro/backend/credentials

# Upload Google Vision API credentials
# On your local machine:
scp path/to/google-vision-credentials.json liquorpro-prod:/opt/liquorpro/backend/credentials/

# Set permissions
chmod 600 /opt/liquorpro/backend/credentials/*.json
```

#### 3.4 Configure Nginx

```bash
# Copy Nginx configurations
sudo cp deployment/nginx/nginx.conf /etc/nginx/nginx.conf
sudo cp deployment/nginx/sites-available/liquorpro.conf /etc/nginx/sites-available/liquorpro.conf
sudo cp deployment/nginx/conf.d/*.conf /etc/nginx/conf.d/

# Update domain name in site config
sudo sed -i 's/yourdomain.com/YOURDOMAIN.com/g' /etc/nginx/sites-available/liquorpro.conf

# Enable site
sudo ln -sf /etc/nginx/sites-available/liquorpro.conf /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

#### 3.5 Initial Deployment

```bash
cd /opt/liquorpro/backend

# Make scripts executable
chmod +x deployment/scripts/*.sh

# Create required directories
mkdir -p /opt/liquorpro/data/{postgres,redis}
mkdir -p /opt/liquorpro/logs/{nginx,gateway,auth,sales,inventory,finance,saas}

# Run initial deployment
./deployment/scripts/deploy-production.sh v1.0.0
```

This will:
1. Pull latest code
2. Build Docker images
3. Start all services
4. Run database migrations
5. Verify health checks

#### 3.6 Verify Deployment

```bash
# Check all services are running
docker-compose -f docker-compose.production.yml ps

# Run health check
./deployment/scripts/health-check-all.sh

# Check logs
docker-compose -f docker-compose.production.yml logs -f gateway
```

**Expected Output**:
```
Total Checks: 15
Passed: 15
Failed: 0
Pass Rate: 100%
✅ System Status: HEALTHY
```

---

### Phase 4: Configure Monitoring (30 minutes)

#### 4.1 Start Monitoring Stack

```bash
cd /opt/liquorpro/backend/deployment/monitoring

# Start Prometheus and Grafana
docker-compose -f docker-compose.monitoring.yml up -d

# Verify monitoring services
docker ps | grep -E "prometheus|grafana"
```

#### 4.2 Access Grafana

```bash
# Grafana is available at:
https://yourdomain.com/grafana

# Default credentials:
Username: admin
Password: <from .env.production GRAFANA_ADMIN_PASSWORD>
```

#### 4.3 Configure Grafana Dashboards

1. Login to Grafana
2. Go to Configuration → Data Sources
3. Prometheus should be auto-configured
4. Import dashboards from `/deployment/monitoring/grafana-dashboards/`

---

### Phase 5: Set Up Automated Backups (15 minutes)

#### 5.1 Configure Backup Script

```bash
# Test backup manually first
./deployment/scripts/backup-all.sh

# Check backup was created
ls -lh /opt/liquorpro/backups/postgres/
```

#### 5.2 Set Up Cron Job

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM UTC:
0 2 * * * /opt/liquorpro/backend/deployment/scripts/backup-all.sh >> /opt/liquorpro/logs/backup.log 2>&1
```

#### 5.3 Configure S3 Backup (Optional)

```bash
# Install AWS CLI
sudo apt-get install awscli -y

# Configure AWS credentials
aws configure

# Update .env.production with S3 details:
BACKUP_S3_BUCKET=liquorpro-backups-prod
BACKUP_S3_REGION=us-east-1
BACKUP_S3_ACCESS_KEY=<your_key>
BACKUP_S3_SECRET_KEY=<your_secret>
```

---

### Phase 6: Configure CI/CD (30 minutes)

#### 6.1 Set Up GitHub Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions

Add these secrets:
- `SSH_PRIVATE_KEY`: Your deploy user's private SSH key
- `SLACK_WEBHOOK_URL`: Slack webhook for notifications (optional)

#### 6.2 Test CI/CD Pipeline

```bash
# Make a small change and push to main
git add .
git commit -m "Test deployment"
git push origin main

# Watch GitHub Actions run
# https://github.com/your-org/liquorpro/actions
```

---

## Post-Deployment Tasks

### 1. Security Hardening

```bash
# Change default Grafana password
docker exec -it liquorpro-grafana grafana-cli admin reset-admin-password <new_password>

# Review firewall rules
sudo ufw status verbose

# Check Fail2ban status
sudo fail2ban-client status sshd
```

### 2. Performance Tuning

```bash
# Monitor resource usage
docker stats

# Check service performance
./deployment/scripts/health-check-all.sh

# Tune database if needed
# See: deployment/docs/PERFORMANCE_TUNING.md
```

### 3. Set Up Monitoring Alerts

Configure AlertManager or use Grafana alerts for:
- Service down
- High error rate
- High resource usage
- SSL certificate expiration
- Backup failures

### 4. Documentation

- [ ] Update team documentation with production URLs
- [ ] Share SSH access with team (deploy user only)
- [ ] Document any custom configurations
- [ ] Create runbook for common issues

---

## Updating the Application

### Standard Update (Zero Downtime)

```bash
# SSH to server
ssh liquorpro-prod

cd /opt/liquorpro/backend

# Deploy new version
./deployment/scripts/deploy-production.sh v1.0.1
```

### Emergency Rollback

```bash
# If deployment fails, rollback immediately:
./deployment/scripts/rollback.sh
```

### Update Configuration

```bash
# Edit environment variables
nano .env.production

# Restart services
docker-compose -f docker-compose.production.yml restart
```

---

## Troubleshooting

### Services Not Starting

```bash
# Check logs
docker-compose -f docker-compose.production.yml logs [service]

# Check resource usage
docker stats

# Check disk space
df -h
```

### Database Connection Issues

```bash
# Check PostgreSQL logs
docker logs liquorpro-postgres-prod

# Connect to database
docker exec -it liquorpro-postgres-prod psql -U liquorpro_prod -d liquorpro_production

# Check connections
SELECT * FROM pg_stat_activity;
```

### Nginx Issues

```bash
# Test configuration
sudo nginx -t

# Check logs
sudo tail -f /var/log/nginx/error.log

# Restart Nginx
sudo systemctl restart nginx
```

### SSL Certificate Issues

```bash
# Check certificate
sudo certbot certificates

# Renew manually
sudo certbot renew --force-renewal

# Check expiration
echo | openssl s_client -connect yourdomain.com:443 2>/dev/null | openssl x509 -noout -dates
```

---

## Maintenance

### Weekly Tasks
- [ ] Check health status
- [ ] Review logs for errors
- [ ] Check disk space
- [ ] Review monitoring dashboards

### Monthly Tasks
- [ ] Test backup restoration
- [ ] Review security logs
- [ ] Update system packages
- [ ] Rotate credentials (if needed)

### Quarterly Tasks
- [ ] Security audit
- [ ] Performance review
- [ ] Disaster recovery drill
- [ ] Documentation update

---

## Support

For issues or questions:
- **Documentation**: `/opt/liquorpro/backend/deployment/docs/`
- **Health Check**: `./deployment/scripts/health-check-all.sh`
- **Logs**: `docker-compose logs -f`
- **GitHub Issues**: https://github.com/your-org/liquorpro/issues

---

## Quick Reference

```bash
# Connect to server
ssh liquorpro-prod

# Deploy new version
./deployment/scripts/deploy-production.sh v1.0.x

# Rollback
./deployment/scripts/rollback.sh

# Health check
./deployment/scripts/health-check-all.sh

# Backup
./deployment/scripts/backup-all.sh

# View logs
docker-compose -f docker-compose.production.yml logs -f [service]

# Restart service
docker-compose -f docker-compose.production.yml restart [service]

# Check status
docker-compose -f docker-compose.production.yml ps
```

---

**Deployment Complete!** 🚀

Your LiquorPro backend is now running in production with:
- ✅ Zero-downtime deployment
- ✅ SSL/TLS encryption (A+ rating)
- ✅ Automated backups
- ✅ Monitoring and alerting
- ✅ CI/CD pipeline
- ✅ Security hardening

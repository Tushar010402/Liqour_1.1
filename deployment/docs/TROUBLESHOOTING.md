# LiquorPro Production Troubleshooting Guide

## Quick Diagnostics

```bash
# Run comprehensive health check
./deployment/scripts/health-check-all.sh

# Check all container status
docker-compose -f docker-compose.production.yml ps

# Check resource usage
docker stats

# Check disk space
df -h

# Check memory
free -h

# Check recent logs
docker-compose -f docker-compose.production.yml logs --tail=100
```

---

## Common Issues

### 1. Service Won't Start

**Symptoms**: Container keeps restarting or exits immediately

**Diagnosis**:
```bash
# Check logs
docker-compose -f docker-compose.production.yml logs [service]

# Check if port is already in use
sudo netstat -tulpn | grep [port]

# Check if environment variables are set
docker-compose -f docker-compose.production.yml config
```

**Solutions**:
```bash
# Fix 1: Check .env.production file exists
ls -la .env.production

# Fix 2: Verify Docker network
docker network ls | grep liquorpro

# Fix 3: Restart service
docker-compose -f docker-compose.production.yml restart [service]

# Fix 4: Rebuild and restart
docker-compose -f docker-compose.production.yml up -d --build [service]
```

---

### 2. Database Connection Failed

**Symptoms**: Services can't connect to PostgreSQL

**Diagnosis**:
```bash
# Check if PostgreSQL is running
docker ps | grep postgres

# Check PostgreSQL logs
docker logs liquorpro-postgres-prod

# Test connection
docker exec -it liquorpro-postgres-prod psql -U liquorpro_prod -d liquorpro_production
```

**Solutions**:
```bash
# Fix 1: Check credentials in .env.production
grep DATABASE .env.production

# Fix 2: Restart PostgreSQL
docker-compose -f docker-compose.production.yml restart postgres

# Fix 3: Check PostgreSQL is accepting connections
docker exec liquorpro-postgres-prod pg_isready

# Fix 4: Check connection pool
docker exec liquorpro-postgres-prod psql -U liquorpro_prod -d liquorpro_production -c "SELECT * FROM pg_stat_activity;"
```

---

### 3. Redis Connection Failed

**Symptoms**: Cache operations failing

**Diagnosis**:
```bash
# Check if Redis is running
docker ps | grep redis

# Check Redis logs
docker logs liquorpro-redis-prod

# Test connection
docker exec -it liquorpro-redis-prod redis-cli ping
```

**Solutions**:
```bash
# Fix 1: Check password
docker exec liquorpro-redis-prod redis-cli -a YOUR_PASSWORD ping

# Fix 2: Restart Redis
docker-compose -f docker-compose.production.yml restart redis

# Fix 3: Check memory
docker exec liquorpro-redis-prod redis-cli INFO memory
```

---

### 4. Nginx 502 Bad Gateway

**Symptoms**: Nginx returns 502 when accessing API

**Diagnosis**:
```bash
# Check Nginx error log
sudo tail -f /var/log/nginx/error.log

# Check if backend services are running
docker-compose -f docker-compose.production.yml ps

# Test backend directly
curl http://localhost:8090/health
```

**Solutions**:
```bash
# Fix 1: Check Nginx config
sudo nginx -t

# Fix 2: Restart Nginx
sudo systemctl restart nginx

# Fix 3: Check upstream backends
grep upstream /etc/nginx/sites-available/liquorpro.conf

# Fix 4: Verify Docker network connectivity
docker exec liquorpro-gateway-prod wget -q -O- http://localhost:8090/health
```

---

### 5. SSL Certificate Issues

**Symptoms**: HTTPS not working or browser shows certificate error

**Diagnosis**:
```bash
# Check certificate status
sudo certbot certificates

# Check certificate expiration
echo | openssl s_client -connect yourdomain.com:443 2>/dev/null | openssl x509 -noout -dates

# Check Nginx SSL config
sudo nginx -t
```

**Solutions**:
```bash
# Fix 1: Renew certificate
sudo certbot renew --force-renewal

# Fix 2: Update Nginx config with correct paths
sudo nano /etc/nginx/sites-available/liquorpro.conf

# Fix 3: Restart Nginx
sudo systemctl restart nginx

# Fix 4: Check firewall allows HTTPS
sudo ufw status | grep 443
```

---

### 6. Out of Disk Space

**Symptoms**: Services failing, can't write files

**Diagnosis**:
```bash
# Check disk usage
df -h

# Find large directories
du -sh /* | sort -hr | head -10

# Check Docker disk usage
docker system df
```

**Solutions**:
```bash
# Clean up Docker
docker system prune -a --volumes -f

# Clean up old logs
find /opt/liquorpro/logs -name "*.log" -mtime +30 -delete

# Clean up old backups
find /opt/liquorpro/backups -name "*.gz" -mtime +30 -delete

# Remove unused Docker images
docker image prune -a -f
```

---

### 7. High Memory Usage

**Symptoms**: System slow, OOM errors

**Diagnosis**:
```bash
# Check memory usage
free -h

# Check container memory usage
docker stats --no-stream

# Check which process uses most memory
ps aux --sort=-%mem | head -10
```

**Solutions**:
```bash
# Restart services
docker-compose -f docker-compose.production.yml restart

# Increase memory limits in docker-compose.production.yml
nano docker-compose.production.yml
# Update: memory: 2G → 4G

# Add swap space (if needed)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

### 8. Deployment Failed

**Symptoms**: Deploy script reports errors

**Diagnosis**:
```bash
# Check last deployment logs
cat /opt/liquorpro/logs/deploy.log

# Check health of services
./deployment/scripts/health-check-all.sh

# Check Git status
git status
git log --oneline -5
```

**Solutions**:
```bash
# Rollback immediately
./deployment/scripts/rollback.sh

# Check for uncommitted changes
git stash

# Try deployment again
./deployment/scripts/deploy-production.sh

# If still fails, check logs
docker-compose -f docker-compose.production.yml logs --tail=200
```

---

### 9. Backup Failed

**Symptoms**: Backup script reports errors

**Diagnosis**:
```bash
# Check backup directory permissions
ls -la /opt/liquorpro/backups/

# Check disk space
df -h /opt/liquorpro/backups

# Test database connection
docker exec liquorpro-postgres-prod pg_isready
```

**Solutions**:
```bash
# Run backup manually with verbose output
./deployment/scripts/backup-all.sh

# Check PostgreSQL connection
docker exec -it liquorpro-postgres-prod psql -U liquorpro_prod -d liquorpro_production

# Verify backup file
ls -lh /opt/liquorpro/backups/postgres/

# Test backup integrity
gunzip -t /opt/liquorpro/backups/postgres/latest-backup.sql.gz
```

---

### 10. Can't SSH to Server

**Symptoms**: SSH connection refused or timeout

**Diagnosis**:
```bash
# Check if server is reachable
ping 72.60.96.174

# Check if SSH port is open
nc -zv 72.60.96.174 2222

# Check from another location
```

**Solutions**:
```bash
# Try default port if custom port fails
ssh -p 22 root@72.60.96.174

# Check SSH service on server (via console)
sudo systemctl status sshd

# Check firewall rules
sudo ufw status

# Restart SSH service
sudo systemctl restart sshd
```

---

## Emergency Procedures

### Complete System Restart

```bash
# Stop all services
docker-compose -f docker-compose.production.yml down

# Wait 10 seconds
sleep 10

# Start all services
docker-compose -f docker-compose.production.yml up -d

# Wait for services to be healthy
sleep 30

# Check health
./deployment/scripts/health-check-all.sh
```

### Database Restore from Backup

```bash
# Stop services
docker-compose -f docker-compose.production.yml stop

# Find latest backup
ls -lt /opt/liquorpro/backups/postgres/ | head -5

# Restore database
gunzip -c /opt/liquorpro/backups/postgres/BACKUP_FILE.sql.gz | \
  docker exec -i liquorpro-postgres-prod psql -U liquorpro_prod -d liquorpro_production

# Start services
docker-compose -f docker-compose.production.yml start

# Verify
./deployment/scripts/health-check-all.sh
```

### Complete Rollback and Restore

```bash
# 1. Rollback application
./deployment/scripts/rollback.sh

# 2. Restore database
# See "Database Restore from Backup" above

# 3. Clear Redis cache
docker exec liquorpro-redis-prod redis-cli FLUSHALL

# 4. Restart all services
docker-compose -f docker-compose.production.yml restart

# 5. Verify
./deployment/scripts/health-check-all.sh
```

---

## Performance Issues

### High CPU Usage

```bash
# Check container CPU usage
docker stats --no-stream

# Check which process
docker exec [container] top

# Restart high-CPU service
docker-compose -f docker-compose.production.yml restart [service]
```

### Slow API Responses

```bash
# Check service logs for slow queries
docker-compose -f docker-compose.production.yml logs [service] | grep -i "slow"

# Check database query performance
docker exec liquorpro-postgres-prod psql -U liquorpro_prod -d liquorpro_production \
  -c "SELECT query, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"

# Check Redis hit rate
docker exec liquorpro-redis-prod redis-cli INFO stats | grep keyspace
```

---

## Monitoring Alerts

### Service Down Alert

```bash
# Check which service is down
docker-compose -f docker-compose.production.yml ps

# Check logs
docker-compose -f docker-compose.production.yml logs [service]

# Restart service
docker-compose -f docker-compose.production.yml restart [service]
```

### High Error Rate Alert

```bash
# Check recent errors
docker-compose -f docker-compose.production.yml logs --tail=500 | grep -i error

# Check specific service
docker-compose -f docker-compose.production.yml logs [service] | grep -i error

# Check Nginx error log
sudo tail -100 /var/log/nginx/error.log
```

---

## Getting Help

If none of these solutions work:

1. **Collect diagnostic information**:
   ```bash
   # Save health check output
   ./deployment/scripts/health-check-all.sh > health-report.txt

   # Save logs
   docker-compose -f docker-compose.production.yml logs --tail=500 > logs.txt

   # Save system info
   docker stats --no-stream > stats.txt
   df -h > disk.txt
   free -h > memory.txt
   ```

2. **Contact support** with the diagnostic files

3. **Check documentation**:
   - `deployment/docs/DEPLOYMENT_GUIDE.md`
   - `deployment/docs/ARCHITECTURE.md`
   - GitHub Issues: https://github.com/your-org/liquorpro/issues

---

## Prevention

To avoid issues:

1. **Regular maintenance**:
   - Run health checks daily
   - Monitor disk space
   - Review logs weekly
   - Update system monthly

2. **Automated monitoring**:
   - Set up Prometheus alerts
   - Configure Grafana dashboards
   - Enable email notifications

3. **Regular backups**:
   - Verify backups run daily
   - Test restore quarterly
   - Keep 30 days of backups

4. **Documentation**:
   - Document all changes
   - Keep runbooks updated
   - Share knowledge with team

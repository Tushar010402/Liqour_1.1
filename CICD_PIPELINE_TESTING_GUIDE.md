# 🚀 CI/CD Pipeline Testing Guide

## Pipeline Overview

Your GitHub Actions CI/CD pipeline automatically deploys to production whenever you push to the `main` branch.

---

## 📋 Pipeline Stages

### **Stage 1: Test** (2-3 minutes)
```
✅ Go vet (static analysis)
✅ Go fmt check (formatting)
✅ Go test with race detection
✅ Code coverage upload to Codecov
```

### **Stage 2: Security Scan** (1-2 minutes)
```
✅ Trivy vulnerability scanner
✅ Upload results to GitHub Security tab
```

### **Stage 3: Build** (5-10 minutes, parallel)
```
Builds 6 Docker images in parallel:
✅ gateway
✅ auth
✅ sales
✅ inventory
✅ finance
✅ saas

Pushes to: ghcr.io/tushar010402/liqour_1.1/[service]:latest
```

### **Stage 4: Deploy** (3-5 minutes)
```
✅ SSH to 72.60.96.174:2222
✅ Pull latest code
✅ Run deployment script
✅ Health checks (all services)
✅ Send Slack notification (if configured)
```

### **Stage 5: Rollback** (if deployment fails)
```
✅ Automatic rollback to previous version
✅ Notification sent
```

**Total Pipeline Time: 10-20 minutes**

---

## 🔐 Required Secrets Setup

### **Step 1: Get Server SSH Private Key**

On your **production server (72.60.96.174)**, run:

```bash
# SSH to server
ssh tushar@72.60.96.174

# Display private key
cat ~/.ssh/id_ed25519
```

**Copy the ENTIRE output**, including:
```
-----BEGIN OPENSSH PRIVATE KEY-----
...all the key content...
-----END OPENSSH PRIVATE KEY-----
```

### **Step 2: Add SSH_PRIVATE_KEY to GitHub**

1. Go to: **https://github.com/Tushar010402/Liqour_1.1/settings/secrets/actions**
2. Click **"New repository secret"**
3. Name: `SSH_PRIVATE_KEY`
4. Value: Paste the private key from Step 1
5. Click **"Add secret"**

### **Step 3: Add SLACK_WEBHOOK_URL (Optional)**

If you want Slack notifications:

1. Create webhook at: https://api.slack.com/messaging/webhooks
2. Go to: https://github.com/Tushar010402/Liqour_1.1/settings/secrets/actions
3. Click **"New repository secret"**
4. Name: `SLACK_WEBHOOK_URL`
5. Value: Your Slack webhook URL
6. Click **"Add secret"**

---

## ✅ Verify Secrets Are Configured

1. Go to: **https://github.com/Tushar010402/Liqour_1.1/settings/secrets/actions**
2. You should see:
   - ✅ `SSH_PRIVATE_KEY` (required)
   - ✅ `SLACK_WEBHOOK_URL` (optional)

---

## 🧪 Test CI/CD Pipeline

### **Method 1: Automatic Test (Make a Small Change)**

Let's make a tiny change to trigger the pipeline:

```bash
# On your local machine
cd /Users/macbookpro/Desktop/Liquor_1.1/Go-Backend-Liquor

# Add a comment to trigger pipeline
echo "# CI/CD Pipeline Test - $(date)" >> CICD_TEST.md

# Commit and push
git add CICD_TEST.md
git commit -m "🧪 Test CI/CD pipeline deployment"
git push origin main
```

### **Method 2: Manual Trigger**

1. Go to: **https://github.com/Tushar010402/Liqour_1.1/actions**
2. Click **"Deploy to Production"** workflow
3. Click **"Run workflow"** button
4. Choose branch: `main`
5. Click **"Run workflow"**

---

## 📊 Monitor Pipeline Execution

### **View Workflow Run**

1. Go to: **https://github.com/Tushar010402/Liqour_1.1/actions**
2. Click on the latest workflow run
3. Watch each stage complete in real-time

### **Expected Output**

```
✅ Test (2-3 min)
   ├─ Checkout code
   ├─ Set up Go
   ├─ Run go vet
   ├─ Run go fmt check
   ├─ Run tests
   └─ Upload coverage

✅ Security Scan (1-2 min)
   ├─ Checkout code
   ├─ Run Trivy scanner
   └─ Upload results

✅ Build (5-10 min, parallel)
   ├─ Build gateway
   ├─ Build auth
   ├─ Build sales
   ├─ Build inventory
   ├─ Build finance
   └─ Build saas

✅ Deploy (3-5 min)
   ├─ Configure SSH
   ├─ Deploy to production
   ├─ Verify deployment
   └─ Send notification

Total: ✅ All jobs completed successfully
```

---

## 🔍 Verify Deployment on Server

After pipeline completes, verify on your server:

```bash
# SSH to server
ssh tushar@72.60.96.174

# Check if services are updated
cd /opt/liquorpro/backend
git log -1

# Check Docker images
docker images | grep liquorpro

# Run health check
./deployment/scripts/health-check-all.sh
```

Expected output:
```
✅ System Status: HEALTHY
Pass Rate: 100%
Total Checks: 20
Passed: 20
Failed: 0
```

---

## 🚨 Troubleshooting

### **Issue 1: SSH Connection Failed**

**Error:** `Permission denied (publickey)`

**Solution:**
```bash
# Verify SSH_PRIVATE_KEY secret is added correctly
# Go to: https://github.com/Tushar010402/Liqour_1.1/settings/secrets/actions

# Ensure the private key includes BEGIN and END lines
# The key should look like:
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtz
...
-----END OPENSSH PRIVATE KEY-----
```

### **Issue 2: Build Failed**

**Error:** `Dockerfile not found`

**Solution:**
```bash
# Check if all Dockerfiles exist
ls -la Dockerfile.*

# Should show:
# Dockerfile.gateway
# Dockerfile.auth
# Dockerfile.sales
# Dockerfile.inventory
# Dockerfile.finance
# Dockerfile.saas
```

### **Issue 3: Tests Failed**

**Error:** `go test failed`

**Solution:**
```bash
# Run tests locally first
go test -v ./...

# Fix any failing tests before pushing
```

### **Issue 4: Deployment Failed**

**Error:** `Health check failed`

**Solution:**
```bash
# SSH to server
ssh tushar@72.60.96.174

# Check service logs
cd /opt/liquorpro/backend
docker-compose -f docker-compose.production.yml logs -f [service_name]

# Run rollback if needed
./deployment/scripts/rollback.sh
```

---

## 📈 Pipeline Success Criteria

Your pipeline is working 100% perfectly when:

- ✅ All tests pass
- ✅ Security scan completes (no critical vulnerabilities blocking)
- ✅ All 6 Docker images build successfully
- ✅ Images push to GitHub Container Registry
- ✅ SSH connection to server succeeds
- ✅ Deployment script runs without errors
- ✅ All health checks pass
- ✅ No rollback triggered
- ✅ Notification sent (if Slack configured)

**Timeline:** Should complete in 10-20 minutes

---

## 🎯 What Happens on Every Push to Main

1. **Developer pushes to main branch**
   ```bash
   git push origin main
   ```

2. **GitHub Actions triggers automatically**
   - No manual intervention needed

3. **Tests run first**
   - If tests fail, pipeline stops (no deployment)
   - If tests pass, continues to build

4. **Security scan runs**
   - Scans for vulnerabilities
   - Reports to GitHub Security tab

5. **Docker images build**
   - All 6 services build in parallel
   - Tagged with commit SHA and 'latest'
   - Pushed to GitHub Container Registry

6. **Deploys to production**
   - SSH to 72.60.96.174
   - Pulls latest code
   - Runs zero-downtime deployment
   - Health checks all services
   - Sends notification

7. **If anything fails**
   - Automatic rollback to previous version
   - Notification sent with error details

---

## 🔄 Manual Deployment (Bypass CI/CD)

If you need to deploy manually without CI/CD:

```bash
# SSH to server
ssh tushar@72.60.96.174

# Navigate to project
cd /opt/liquorpro/backend

# Pull latest code
git pull origin main

# Run deployment script
./deployment/scripts/deploy-production.sh v1.0.1
```

---

## 📊 View Pipeline Metrics

### **GitHub Actions Dashboard**
- URL: https://github.com/Tushar010402/Liqour_1.1/actions
- Shows all workflow runs
- Success/failure rates
- Execution times

### **Container Registry**
- URL: https://github.com/Tushar010402?tab=packages
- Shows all Docker images
- Image sizes
- Download counts

### **Security Tab**
- URL: https://github.com/Tushar010402/Liqour_1.1/security
- Vulnerability reports from Trivy
- Dependabot alerts

---

## 🎓 Best Practices

1. **Always test locally before pushing**
   ```bash
   go test -v ./...
   go vet ./...
   gofmt -s -w .
   ```

2. **Use feature branches for development**
   ```bash
   git checkout -b feature/new-feature
   # ... make changes ...
   git push origin feature/new-feature
   # Create PR, then merge to main
   ```

3. **Monitor deployment in real-time**
   - Watch GitHub Actions tab during deployment
   - Check server health checks after deployment

4. **Keep secrets secure**
   - Never commit secrets to repository
   - Use GitHub Secrets for sensitive data
   - Rotate SSH keys periodically

5. **Review security scan results**
   - Check Security tab weekly
   - Update dependencies to fix vulnerabilities

---

## 🚀 Quick Test Command

Run this to test your CI/CD pipeline right now:

```bash
cd /Users/macbookpro/Desktop/Liquor_1.1/Go-Backend-Liquor

# Create test file
echo "# CI/CD Pipeline Test - $(date)" > CICD_TEST.md

# Commit and push
git add CICD_TEST.md
git commit -m "🧪 Test CI/CD pipeline - $(date +%Y%m%d-%H%M%S)"
git push origin main

echo ""
echo "✅ Pushed to GitHub!"
echo "📊 Watch pipeline at: https://github.com/Tushar010402/Liqour_1.1/actions"
echo ""
```

Then open: **https://github.com/Tushar010402/Liqour_1.1/actions**

---

## ✅ Pipeline Verification Checklist

After running a test deployment:

- [ ] GitHub Actions workflow started automatically
- [ ] Test stage passed (green checkmark)
- [ ] Security scan completed
- [ ] All 6 Docker images built successfully
- [ ] Deploy stage completed
- [ ] Health checks passed on server
- [ ] Services are running on server (`docker ps`)
- [ ] API endpoints responding (`curl https://yourdomain.com/gateway/health`)
- [ ] No errors in logs
- [ ] Notification received (if Slack configured)

---

**Your CI/CD pipeline is ready! Test it now with the Quick Test Command above.** 🚀

# OCR Improvements - Quick Command Reference

**Keep this handy!** All the commands you'll need for day-to-day operations.

---

## 🚀 Essential Commands

### Verify Everything is Working
```bash
cd /var/www/liquorpro
./scripts/verify_deployment.sh
```
**Expected**: 20/20 checks pass ✅
**Run**: After deployment, before monitoring

---

### Start Production Monitoring
```bash
./scripts/ocr_metrics_monitor.sh 60      # Monitor for 1 hour
./scripts/ocr_metrics_monitor.sh 30      # Monitor for 30 minutes
./scripts/ocr_metrics_monitor.sh 120     # Monitor for 2 hours
```
**What you'll see**: Real-time dashboard with all metrics
**Run**: During OCR processing to see improvements

---

### Check Recent Logs
```bash
# Last 100 lines
sudo docker logs liquorpro-sales-prod --tail 100

# Last hour only
sudo docker logs liquorpro-sales-prod --since 1h

# Follow live
sudo docker logs -f liquorpro-sales-prod
```
**Look for**: Fuzzy detection, cache hits, validation results

---

### Search for Improvements
```bash
# All improvements in last hour
sudo docker logs liquorpro-sales-prod --since 1h | grep -E "Fuzzy|Cache|Validation"

# Just cache performance
sudo docker logs liquorpro-sales-prod | grep "Cache HIT\|Cache MISS"

# Just fuzzy detection
sudo docker logs liquorpro-sales-prod | grep "Fuzzy matched"

# Just validation
sudo docker logs liquorpro-sales-prod | grep "Cross-Field Validation"
```
**Use**: To verify specific improvements are working

---

### Run Performance Benchmarks
```bash
./scripts/ocr_benchmark.sh
```
**Expected**: 24/24 tests passing
**Run**: Weekly or after changes

---

### Run Unit Tests (Requires Go)
```bash
# All tests
./scripts/ocr_test_runner.sh

# Verbose mode
./scripts/ocr_test_runner.sh --verbose

# With coverage
./scripts/ocr_test_runner.sh --coverage
```
**Expected**: 50+ tests passing
**Run**: Before deploying changes

---

## 📊 Monitoring Metrics

### Calculate Cache Hit Rate
```bash
HITS=$(sudo docker logs liquorpro-sales-prod --since 1h | grep -c "Cache HIT")
MISSES=$(sudo docker logs liquorpro-sales-prod --since 1h | grep -c "Cache MISS")
TOTAL=$((HITS + MISSES))
echo "Cache hits: $HITS, Misses: $MISSES"
[ $TOTAL -gt 0 ] && echo "Hit rate: $(awk "BEGIN {printf \"%.1f%%\", ($HITS / $TOTAL) * 100}")"
```
**Target**: ~70% hit rate after warm-up

---

### Count Improvements in Action
```bash
echo "=== OCR Improvements (last hour) ==="
echo "Fuzzy detections: $(sudo docker logs liquorpro-sales-prod --since 1h | grep -c 'Fuzzy matched')"
echo "Cache hits: $(sudo docker logs liquorpro-sales-prod --since 1h | grep -c 'Cache HIT')"
echo "Validations: $(sudo docker logs liquorpro-sales-prod --since 1h | grep -c 'Cross-Field Validation')"
```
**Use**: Quick health check

---

### Check Container Status
```bash
# Is it running?
sudo docker ps | grep sales

# Container details
sudo docker inspect liquorpro-sales-prod --format='{{.State.Status}}'

# When was it created?
sudo docker inspect liquorpro-sales-prod --format='{{.Created}}'

# Resource usage
sudo docker stats liquorpro-sales-prod --no-stream
```
**Use**: Troubleshooting container issues

---

## 📚 Documentation Commands

### Read Documentation
```bash
# Main README
cat README_OCR_IMPROVEMENTS.md

# Quick reference
cat OCR_QUICK_REFERENCE.md

# Current status
cat PROJECT_STATUS.md

# Troubleshooting
cat TROUBLESHOOTING_FAQ.md

# For executives
cat EXECUTIVE_SUMMARY.md
```
**Tip**: Start with Quick Reference!

---

### Search Documentation
```bash
# Find keyword in all docs
grep -r "your_keyword" *.md

# Case-insensitive search
grep -ri "keyword" *.md

# Show line numbers
grep -rn "keyword" *.md
```
**Use**: Find answers fast

---

## 🔧 Troubleshooting Commands

### Fix Script Permissions
```bash
chmod +x scripts/*.sh
```
**Run**: If you get "Permission denied"

---

### Restart Container
```bash
sudo docker restart liquorpro-sales-prod

# Check it restarted
sudo docker ps | grep sales
```
**Use**: If container is misbehaving

---

### Clear Container Logs
```bash
# Truncate logs (be careful!)
sudo docker logs liquorpro-sales-prod 2>&1 | tail -1000 > /tmp/recent.log
```
**Use**: If logs are too large

---

### Check Disk Space
```bash
df -h
sudo docker system df
```
**Use**: If running out of space

---

## 📈 Performance Analysis

### Count Items Processed
```bash
# Items in last hour
sudo docker logs liquorpro-sales-prod --since 1h | grep -c "Extracted item"

# Gemini API calls
sudo docker logs liquorpro-sales-prod --since 1h | grep -c "Gemini.*API call"
```
**Compare**: Items vs API calls (should be ~30%)

---

### Check Error Rates
```bash
# Critical errors
sudo docker logs liquorpro-sales-prod --since 1h | grep -c "CRITICAL"

# Warnings
sudo docker logs liquorpro-sales-prod --since 1h | grep -c "WARNING\|WARN"

# JSON repair failures
sudo docker logs liquorpro-sales-prod --since 1h | grep -c "JSON Repair.*Failed"
```
**Target**: Critical < 5%, Warnings < 20%

---

## 🎯 Quick Diagnostics

### One-Liner Health Check
```bash
./scripts/verify_deployment.sh | grep -E "Passed:|Status:"
```
**Expected**: Passed: 20, Status: READY

---

### See What's Happening Now
```bash
sudo docker logs liquorpro-sales-prod --tail 20 | grep -E "OCR|Fuzzy|Cache|Validation"
```
**Use**: Quick peek at current activity

---

### Full System Check
```bash
echo "=== System Health Check ==="
echo "Container: $(sudo docker ps | grep -q liquorpro-sales-prod && echo "Running ✅" || echo "Not running ❌")"
echo "Scripts: $(ls scripts/*.sh | wc -l) found"
echo "Docs: $(ls *.md | wc -l) found"
echo ""
echo "Recent activity:"
sudo docker logs liquorpro-sales-prod --tail 50 | grep -E "Fuzzy|Cache|Validation" | tail -5
```
**Use**: Overall status check

---

## 🔍 Common Log Patterns

### Good Signs (What to Look For)
```bash
# These are GOOD
🔧 [OCR] Fuzzy matched 90ml using pattern
💨 [Cache HIT] 'Brand' → 'Brand' (saved API call)
✅ [Cross-Field Validation] All checks passed
💰 [Price] Direct extraction - Rate column
```

### Warning Signs (Normal but Watch)
```bash
# These are OK in moderation
⚠️ [Cross-Field Validation] Found 1 warnings
🔧 [OCR] Fixed missing size
💰 [Price] Fallback calculation
```

### Red Flags (Investigate These)
```bash
# These need attention
❌ [Cross-Field Validation] CRITICAL
🔧 [JSON Repair] Failed to repair JSON
ERROR:
FATAL:
```

---

## 📋 Daily Operations Checklist

### Morning Check
```bash
# 1. Container running?
sudo docker ps | grep sales

# 2. Any errors overnight?
sudo docker logs liquorpro-sales-prod --since 12h | grep -i error | wc -l

# 3. Quick verification
./scripts/verify_deployment.sh | tail -10
```

### During Peak Hours
```bash
# Monitor live
./scripts/ocr_metrics_monitor.sh 60
```

### End of Day
```bash
# Review stats
sudo docker logs liquorpro-sales-prod --since 1d | grep -E "Fuzzy|Cache|Validation" | wc -l
```

---

## 🆘 Emergency Commands

### Container Won't Start
```bash
# Check status
sudo docker ps -a | grep sales

# View logs
sudo docker logs liquorpro-sales-prod

# Restart
sudo docker restart liquorpro-sales-prod
```

### High Error Rate
```bash
# See errors
sudo docker logs liquorpro-sales-prod --tail 100 | grep -i error

# Check recent images processed
sudo docker logs liquorpro-sales-prod --tail 100 | grep "Processing image"
```

### Out of Disk Space
```bash
# Check space
df -h
sudo docker system df

# Clean up
sudo docker system prune -f
```

---

## 📖 Help Resources

| Need | Command |
|------|---------|
| **Quick reference** | `cat OCR_QUICK_REFERENCE.md` |
| **Troubleshooting** | `cat TROUBLESHOOTING_FAQ.md` |
| **Full docs** | `cat README_OCR_IMPROVEMENTS.md` |
| **Current status** | `cat PROJECT_STATUS.md` |
| **Executive summary** | `cat EXECUTIVE_SUMMARY.md` |

---

## 💡 Pro Tips

1. **Bookmark this file** for quick reference
2. **Alias common commands**:
   ```bash
   alias ocr-monitor='./scripts/ocr_metrics_monitor.sh 60'
   alias ocr-verify='./scripts/verify_deployment.sh'
   alias ocr-logs='sudo docker logs liquorpro-sales-prod'
   ```
3. **Create shortcuts** in your `.bashrc`:
   ```bash
   export OCR_DIR="/var/www/liquorpro"
   alias cdocr='cd $OCR_DIR'
   ```
4. **Use tab completion** for long paths
5. **Pipe to less** for long output: `command | less`

---

## 🎯 Most Used Commands (Top 5)

```bash
# 1. Monitor production (use daily)
./scripts/ocr_metrics_monitor.sh 60

# 2. Check recent logs (use hourly)
sudo docker logs liquorpro-sales-prod --tail 100

# 3. Verify deployment (use weekly)
./scripts/verify_deployment.sh

# 4. Search for improvements (use as needed)
sudo docker logs liquorpro-sales-prod | grep -E "Fuzzy|Cache|Validation"

# 5. Quick status check (use anytime)
sudo docker ps | grep sales
```

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0
**Print this**: Keep next to your desk!

---

> **Remember**: When in doubt, run `./scripts/verify_deployment.sh` first. It checks everything and gives clear guidance!

**Quick Help**: `cat TROUBLESHOOTING_FAQ.md`

# OCR Improvements - Troubleshooting FAQ

**Quick Navigation**: [Scripts](#scripts-issues) | [Monitoring](#monitoring-issues) | [Tests](#testing-issues) | [Production](#production-issues) | [Performance](#performance-issues)

---

## 🚨 Common Issues & Solutions

### Scripts Issues

#### Q: Script won't run - "Permission denied"

**Error**:
```bash
bash: ./scripts/ocr_test_runner.sh: Permission denied
```

**Solution**:
```bash
# Make all scripts executable
chmod +x scripts/*.sh

# Or individually
chmod +x scripts/ocr_test_runner.sh
chmod +x scripts/ocr_metrics_monitor.sh
chmod +x scripts/ocr_benchmark.sh
chmod +x scripts/verify_deployment.sh
```

**Verify**:
```bash
ls -l scripts/*.sh | grep '^-rwx'
```

---

#### Q: Test runner says "Go is not installed"

**Error**:
```
Error: Go is not installed!
This script requires Go to run unit tests.
```

**Explanation**: The test runner requires Go 1.19+ for development environments.

**Solution 1 - Install Go** (if you need to run tests):
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install golang-go

# macOS
brew install go

# Or download from: https://golang.org/doc/install
```

**Solution 2 - Skip tests** (if you just want monitoring):
```bash
# You don't need Go for monitoring
./scripts/ocr_metrics_monitor.sh 60

# Or benchmarking
./scripts/ocr_benchmark.sh
```

**Note**: Production containers don't need Go - they use compiled binaries.

---

#### Q: Monitoring script shows syntax errors

**Error**:
```
line 82: 0
0: syntax error in expression (error token is "0")
```

**Solution**: This has been fixed in the latest version. If you see this:

```bash
# Re-download or verify you have the latest version
grep "tr -d" scripts/ocr_metrics_monitor.sh

# Should show lines that clean variables
```

**If still broken**, the issue is with variable cleaning. The script should have:
```bash
cache_hits=$(echo "$cache_hits" | tr -d '\n' | tr -d ' ')
cache_hits=${cache_hits:-0}
```

---

### Monitoring Issues

#### Q: Dashboard shows all zeros

**Display**:
```
Fuzzy Size Detections:      0 times
Cache Hits:                 0
Validation Passed:          0 items
```

**Explanation**: This is NORMAL when there's no OCR activity.

**Solution**: This is expected behavior. The metrics populate when OCR processing occurs.

**To verify it works**:
1. Process a test batch of invoices
2. Run monitoring during processing
3. You should see numbers start appearing

**Quick test**:
```bash
# Check if there's any recent OCR activity
sudo docker logs liquorpro-sales-prod --since 1h | grep -i "ocr\|brand\|extract" | head -10

# If no output, no recent OCR activity (hence zeros)
```

---

#### Q: "Container is not running" error

**Error**:
```
Error: Container liquorpro-sales-prod is not running!
```

**Solution**:
```bash
# Check container status
sudo docker ps -a | grep sales

# If stopped, start it
sudo docker start liquorpro-sales-prod

# If doesn't exist, check container name
sudo docker ps | grep sales

# Update script with correct name if needed
```

**Common container names**:
- `liquorpro-sales-prod`
- `liquorpro-sales`
- `sales-service`

---

#### Q: Dashboard doesn't refresh / updates

**Symptom**: Dashboard shows same numbers, time doesn't update

**Solution**:
```bash
# Kill the script
Ctrl+C

# Restart it
./scripts/ocr_metrics_monitor.sh 60

# If still stuck, check terminal size
echo $COLUMNS $LINES
# Should show numbers like: 80 24
```

---

### Testing Issues

#### Q: Tests fail with import errors

**Error**:
```
package github.com/liquorpro/go-backend/pkg/ocr: cannot find package
```

**Solution**:
```bash
# Navigate to project root
cd /var/www/liquorpro

# Download dependencies
go mod download

# Verify go.mod exists
ls go.mod

# Try again
./scripts/ocr_test_runner.sh
```

---

#### Q: Specific test fails

**Error**:
```
--- FAIL: TestValidatePriceRange (0.00s)
    ocr_service_test.go:450: Expected true, got false
```

**Solution**:
```bash
# Run in verbose mode to see details
./scripts/ocr_test_runner.sh --verbose

# Run just that specific test
go test -v -run TestValidatePriceRange ./internal/sales/services

# Check if code was modified
git diff internal/sales/services/ocr_service.go
```

**Common causes**:
- Code was modified breaking test expectations
- Price range constants changed
- Validation logic updated

---

#### Q: Coverage report won't generate

**Error**:
```
go tool cover: HTML generation failed
```

**Solution**:
```bash
# Check if coverage directory exists
mkdir -p coverage

# Try manual coverage generation
cd /var/www/liquorpro
go test -coverprofile=coverage/test.out ./internal/sales/services
go tool cover -html=coverage/test.out -o coverage/report.html

# Open in browser
firefox coverage/report.html
```

---

### Production Issues

#### Q: OCR accuracy not improving

**Symptom**: Still seeing same accuracy as before (~62%)

**Diagnostic steps**:

1. **Verify improvements are deployed**:
```bash
# Check for improvement indicators in logs
sudo docker logs liquorpro-sales-prod --tail 100 | grep -E "Fuzzy|Cache|Validation"

# Should see lines like:
# 🔧 [OCR] Fuzzy matched 90ml
# 💨 [Cache HIT]
# ✅ [Cross-Field Validation]
```

2. **Check container creation date**:
```bash
sudo docker inspect liquorpro-sales-prod --format='{{.Created}}'

# Should be recent (after deployment date)
```

3. **Verify code is present**:
```bash
# Check for fuzzy detection
sudo docker exec liquorpro-sales-prod grep -q "Fuzzy matched" /app/internal/sales/services/ocr_service.go 2>/dev/null && echo "Code present" || echo "Code missing"
```

**If code is missing**: Container needs to be rebuilt with latest code.

---

#### Q: Cache hit rate is very low (<30%)

**Expected**: ~70% cache hit rate
**Actual**: <30%

**Possible causes**:

1. **Cache not warmed up yet**:
   - First batch won't have cache hits
   - Give it 2-3 batches to warm up
   - Monitor: `./scripts/ocr_metrics_monitor.sh 30`

2. **Many unique brands**:
   - If every invoice has different brands, lower hit rate is normal
   - Check: `sudo docker logs liquorpro-sales-prod | grep "Cache MISS" | wc -l`

3. **Cache TTL too short**:
   - Default: 1 hour
   - If batches are >1 hour apart, cache expires
   - Check logs for "Cache expired" messages

**Solution**: If TTL needs adjustment, it's in `pkg/ocr/gemini_client.go:76`

---

#### Q: High critical validation failures (>10%)

**Symptom**: Dashboard shows many critical failures

**Diagnostic**:
```bash
# Check what's failing
sudo docker logs liquorpro-sales-prod | grep "CRITICAL"

# Common patterns:
# - Negative prices
# - Invalid quantities
# - Malformed data
```

**Solutions**:

1. **If negative prices**:
   - Check invoice quality
   - May need OCR quality improvements

2. **If data format issues**:
   - Verify invoice format matches expected
   - May need to adjust validation thresholds

3. **If many failures on specific brand**:
   - Review that specific invoice
   - May be corrupt/damaged image

---

#### Q: JSON repair failures

**Error in logs**:
```
[JSON Repair] Failed to repair JSON after 6 attempts
```

**Cause**: Gemini returning severely malformed JSON

**Solutions**:

1. **Check Gemini API status**:
```bash
# Test API connectivity
curl -H "Content-Type: application/json" \
  "https://generativelanguage.googleapis.com/v1beta/models"
```

2. **Review the raw Gemini response**:
```bash
# Look for Gemini responses in logs
sudo docker logs liquorpro-sales-prod | grep -A5 "Gemini.*response"
```

3. **Check image quality**:
   - Blurry images → poor OCR → bad Gemini input
   - Try with higher quality image

---

### Performance Issues

#### Q: OCR processing is slow

**Symptom**: Taking longer than before

**Diagnostic**:

1. **Check cache performance**:
```bash
./scripts/ocr_metrics_monitor.sh 10

# Look for cache hit rate
# Should be ~70%
```

2. **Check API call count**:
```bash
# Count Gemini calls
sudo docker logs liquorpro-sales-prod --since 1h | grep -c "Gemini.*API call"

# Should be ~30% of item count
```

3. **Check for retries**:
```bash
# Look for retry patterns
sudo docker logs liquorpro-sales-prod | grep -i "retry"
```

**Solutions**:

- **If cache not working**: Check for cache errors in logs
- **If many retries**: Investigate why (API errors? timeouts?)
- **If API calls high**: Cache may not be working

---

#### Q: Memory usage increased

**Symptom**: Container using more memory

**Check**:
```bash
# Check container stats
sudo docker stats liquorpro-sales-prod --no-stream

# Look at MEM USAGE / LIMIT
```

**Explanation**: Cache uses some memory, but should be minimal (<100MB)

**If excessive (>500MB for cache)**:
```bash
# Check cache size in logs
sudo docker logs liquorpro-sales-prod | grep -i "cache.*size\|cache.*cleanup"

# Cache cleanup should run every 15 minutes
```

**Solution**: Cache cleanup should handle this automatically. If not, container restart clears cache:
```bash
sudo docker restart liquorpro-sales-prod
```

---

## 🔍 Diagnostic Commands

### Quick Health Check

```bash
# All-in-one verification
./scripts/verify_deployment.sh

# Should show mostly green checkmarks
```

### Check Recent OCR Activity

```bash
# Last 100 log lines
sudo docker logs liquorpro-sales-prod --tail 100

# Last hour of OCR activity
sudo docker logs liquorpro-sales-prod --since 1h | grep -i "extract\|brand\|ocr"

# Count improvements in action
sudo docker logs liquorpro-sales-prod --since 1h | grep -c "Fuzzy\|Cache HIT\|Validation"
```

### Monitor Live Logs

```bash
# Follow logs in real-time
sudo docker logs -f liquorpro-sales-prod

# Filter for improvements
sudo docker logs -f liquorpro-sales-prod | grep --line-buffered -E "Fuzzy|Cache|Validation"
```

### Check Specific Improvements

```bash
# Phase 1: Fuzzy detection
sudo docker logs liquorpro-sales-prod | grep "Fuzzy matched"

# Phase 2: Cache
sudo docker logs liquorpro-sales-prod | grep "Cache HIT\|Cache MISS"

# Phase 3: Validation
sudo docker logs liquorpro-sales-prod | grep "Cross-Field Validation"
```

### Performance Metrics

```bash
# Cache hit rate calculation
HITS=$(sudo docker logs liquorpro-sales-prod --since 1h | grep -c "Cache HIT")
MISSES=$(sudo docker logs liquorpro-sales-prod --since 1h | grep -c "Cache MISS")
TOTAL=$((HITS + MISSES))
if [ $TOTAL -gt 0 ]; then
  echo "Cache hit rate: $(awk "BEGIN {printf \"%.1f%%\", ($HITS / $TOTAL) * 100}")"
fi
```

---

## 📋 Verification Checklist

Use this to verify everything is working:

### Initial Setup
- [ ] All scripts are executable (`ls -l scripts/*.sh`)
- [ ] Container is running (`sudo docker ps | grep sales`)
- [ ] Documentation is present (`ls *OCR*.md`)

### First Test
- [ ] Run verification: `./scripts/verify_deployment.sh`
- [ ] All checks pass or have acceptable warnings
- [ ] No critical failures

### First Monitoring Session
- [ ] Dashboard starts without errors
- [ ] Metrics display (even if zeros)
- [ ] Auto-refresh works
- [ ] Ctrl+C exits cleanly

### During OCR Processing
- [ ] Metrics populate (non-zero values)
- [ ] Cache hits appear
- [ ] Fuzzy detections trigger
- [ ] Validation runs

### After Processing
- [ ] Cache hit rate ~70%
- [ ] Validation pass rate >90%
- [ ] Critical failures <5%
- [ ] Logs show improvement indicators

---

## 🆘 Still Stuck?

### Step-by-Step Debug Process

1. **Run deployment verification**:
   ```bash
   ./scripts/verify_deployment.sh
   ```
   Fix any critical failures shown.

2. **Check container status**:
   ```bash
   sudo docker ps -a | grep sales
   ```
   Ensure it's running (not stopped/restarting).

3. **Review recent logs**:
   ```bash
   sudo docker logs liquorpro-sales-prod --tail 50
   ```
   Look for obvious errors.

4. **Test with monitoring**:
   ```bash
   ./scripts/ocr_metrics_monitor.sh 5
   ```
   Should run for 5 minutes without errors.

5. **Search documentation**:
   ```bash
   # Search all docs for keyword
   grep -r "your_error_message" *.md
   ```

---

## 📞 Where to Find Help

| Issue Type | Resource |
|------------|----------|
| **Quick answer** | `OCR_QUICK_REFERENCE.md` |
| **Script usage** | `scripts/README_OCR_TESTING.md` |
| **Technical details** | `CHANGELOG_OCR_IMPROVEMENTS.md` |
| **Code questions** | Review test file: `ocr_service_test.go` |
| **Production issues** | This FAQ + monitoring logs |
| **General guidance** | `NEXT_STEPS.md` |

---

## 💡 Pro Tips

1. **Start with verification**: Always run `./scripts/verify_deployment.sh` first
2. **Check logs first**: Most issues show clear error messages in logs
3. **Use monitoring**: Dashboard reveals most production issues
4. **Read error messages**: They usually tell you exactly what's wrong
5. **Search docs**: `grep -r "keyword" *.md` finds relevant sections fast

---

## 🎯 Expected Behavior Summary

### Normal Behavior ✅

- **Dashboard shows zeros** when no OCR activity (expected)
- **Cache hit rate low initially** (needs warm-up)
- **Some validation warnings** (<20% is normal)
- **Test runner requires Go** (by design)
- **Script needs executable permissions** (use chmod +x)

### Warning Signs ⚠️

- **Cache hit rate <50%** after warm-up (investigate)
- **Validation pass rate <80%** (check data quality)
- **Many JSON repair failures** (Gemini API issues?)
- **Container frequently restarting** (resource issues?)

### Critical Issues 🚨

- **No improvement indicators in logs** (code not deployed?)
- **Container not running** (deployment issue)
- **All tests failing** (code broken)
- **Validation failures >50%** (data quality crisis)

---

## 📝 Reporting Issues

If you find a genuine issue, document:

1. **What you were doing**: Exact command run
2. **What happened**: Error message or unexpected behavior
3. **What you expected**: What should have happened
4. **Environment**: Container name, OS, Docker version
5. **Logs**: Relevant log snippets
6. **Steps tried**: What you've attempted to fix it

Include output from:
```bash
./scripts/verify_deployment.sh > verification.log 2>&1
sudo docker logs liquorpro-sales-prod --tail 200 > container.log 2>&1
```

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0
**Status**: Comprehensive FAQ covering all known issues

---

> **Remember**: Most issues have simple solutions. Check logs, verify deployment, and search the documentation. 99% of issues are covered here or in the other guides!

# OCR Development - Quick Cheat Sheet

**Purpose**: 1-page reference for daily development
**Print**: Keep at your desk for quick lookups
**Last Updated**: January 15, 2025

---

## 🚀 Essential Commands (Top 10)

```bash
# 1. Verify everything works
./scripts/verify_deployment.sh

# 2. Run all tests
./scripts/ocr_test_runner.sh

# 3. Monitor production (60 min)
./scripts/ocr_metrics_monitor.sh 60

# 4. Check recent logs
sudo docker logs liquorpro-sales-prod --tail 100

# 5. Search for errors
sudo docker logs liquorpro-sales-prod --since 1h | grep -i error

# 6. Run specific test
go test -run TestFuzzyPatterns ./internal/sales/services

# 7. Check container status
sudo docker ps | grep sales

# 8. View live logs
sudo docker logs -f liquorpro-sales-prod

# 9. Restart container
sudo docker restart liquorpro-sales-prod

# 10. Test with race detection
go test -race ./pkg/ocr
```

---

## 📝 Code Patterns (Copy-Paste Ready)

### Add Fuzzy Pattern
```go
// In detectReceiptType function
sizeXXXPatterns := []string{
    `XX[0oO]\s*m[\.\s]*l`,  // Handles: XXml, XXOml, XX m.l
    `alias_name`,            // Common alias
}

for _, pattern := range sizeXXXPatterns {
    if matched, _ := regexp.MatchString(pattern, textLower); matched {
        fmt.Printf("🔧 [OCR] Fuzzy matched XXXml using pattern: %s\n", pattern)
        return "XXXml"
    }
}
```

### Add Validation Rule
```go
// In validateCrossFields function
if brand.YourField /* condition */ {
    result.Issues = append(result.Issues, "Your validation message")
    result.WarningCount++  // or CriticalCount
}
```

### Add Cache Check
```go
// Check cache first
c.cacheMutex.RLock()
entry, exists := c.yourCache[key]
c.cacheMutex.RUnlock()

if exists && time.Since(entry.timestamp) < c.cacheTTL {
    fmt.Printf("💨 [Cache HIT] '%s'\n", key)
    return entry.value, nil
}

// Update cache after operation
c.cacheMutex.Lock()
c.yourCache[key] = yourCacheEntry{
    value:     result,
    timestamp: time.Now(),
}
c.cacheMutex.Unlock()
```

### Add Table-Driven Test
```go
func TestYourFunction(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected string
    }{
        {"Happy path", "input1", "expected1"},
        {"Edge case", "input2", "expected2"},
        {"Error case", "input3", "expected3"},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := YourFunction(tt.input)
            if result != tt.expected {
                t.Errorf("Expected %s, got %s", tt.expected, result)
            }
        })
    }
}
```

### Add Structured Logging
```go
fmt.Printf("🔧 [Component] Action for '%s'\n", item)
fmt.Printf("💨 [Component] Fast path for '%s'\n", item)
fmt.Printf("✅ [Component] Success for '%s'\n", item)
fmt.Printf("⚠️  [Component] Warning for '%s': %s\n", item, warning)
fmt.Printf("❌ [Component] Error for '%s': %v\n", item, err)
```

---

## 🎯 Key Metrics to Track

```
Accuracy:           Target: >95%    Alert: <90%
Cache Hit Rate:     Target: >70%    Alert: <50%
API Call Reduction: Target: >60%    Measure: Daily
Validation Pass:    Target: >90%    Alert: <85%
Test Coverage:      Target: >80%    Minimum: 75%
Error Rate:         Target: <5%     Alert: >10%
Manual Reviews:     Target: <10%    Alert: >20%
```

---

## 🔍 OCR Error Patterns

```
Common OCR Misreads:
0 ↔ O (zero ↔ letter O)
1 ↔ l ↔ I (one ↔ lowercase L ↔ capital i)
5 ↔ S (five ↔ letter S)
8 ↔ B (eight ↔ letter B)
2 ↔ Z (two ↔ letter Z)
6 ↔ G (six ↔ letter G)

Handle with character classes:
[0oO]  [1lI]  [5sS]  [8bB]
```

---

## ✅ Pre-Commit Checklist

```
□ Tests written and passing
□ Coverage >80% for new code
□ No race conditions (go test -race)
□ Errors handled explicitly (no _ ignoring)
□ Logging is structured
□ Documentation updated
□ Self-reviewed with checklist
□ No TODO without ticket
```

---

## 🚨 When Things Go Wrong

```
Symptom               → Check
─────────────────────────────────────────
Low accuracy          → grep "Fuzzy matched" logs
High API costs        → Check cache hit rate
Container crashes     → docker logs + grep "fatal"
Race conditions       → go test -race
Memory leak           → Check cache cleanup
Tests failing         → Run with -v flag
Pattern not matching  → Test in regex101.com
```

---

## 📊 Log Emoji Guide

```
🔧  Info/Normal operations
💨  Cache hits, fast paths
✅  Success, validation passed
⚠️   Warnings, review needed
❌  Errors, failures
🔍  Debug information
💰  Price-related operations
```

---

## 🔢 Price Ranges by Size

```
Size     Min    Max    Typical
────────────────────────────────
90ml     ₹40    ₹300   ₹120-180
180ml    ₹80    ₹500   ₹200-350
375ml    ₹150   ₹1000  ₹400-700
750ml    ₹300   ₹3000  ₹800-1500
```

---

## 📁 Key File Locations

```
Code:
  internal/sales/services/ocr_service.go      (Main OCR logic)
  pkg/ocr/gemini_client.go                     (API client)
  internal/sales/services/ocr_service_test.go  (Tests)

Scripts:
  scripts/ocr_test_runner.sh         (Run tests)
  scripts/ocr_metrics_monitor.sh     (Monitor)
  scripts/verify_deployment.sh       (Verify)

Docs:
  BEST_PRACTICES_INDEX.md            (Start here)
  OCR_DEVELOPMENT_GUIDE.md           (How-to)
  COMMON_PITFALLS.md                 (Avoid)
  CODE_REVIEW_CHECKLIST.md           (Review)
```

---

## 🎓 Learning Resources

```
New to Project:
  1. OCR_DEVELOPMENT_GUIDE.md → Your First Day
  2. REAL_WORLD_EXAMPLES.md → Phase 1 examples
  3. Hands-on: Add one fuzzy pattern

Need Help:
  - TROUBLESHOOTING_FAQ.md
  - grep -r "keyword" *.md
  - Ask team on Slack/Teams

Code Review:
  - CODE_REVIEW_CHECKLIST.md
  - BEST_PRACTICES.md
  - COMMON_PITFALLS.md
```

---

## ⚡ Performance Tips

```
✅ DO:
- Compile regex once (var pattern = regexp.MustCompile())
- Use cache for repeated API calls
- Use RWMutex (read locks don't block each other)
- Profile before optimizing
- Set cache TTL (1 hour is good)

❌ DON'T:
- Compile regex in loops
- Ignore cache misses
- Use map without mutex
- Optimize without measuring
- Cache forever (memory leak)
```

---

## 🔄 Quick Deployment

```bash
# Build
sudo -E bash -c "set -a; source .env.production 2>/dev/null; set +a; \
  docker compose -f docker-compose.production.yml build sales"

# Deploy
sudo -E bash -c "set -a; source .env.production 2>/dev/null; set +a; \
  docker compose -f docker-compose.production.yml up -d --no-deps sales"

# Verify
./scripts/verify_deployment.sh

# Monitor (30 min minimum!)
./scripts/ocr_metrics_monitor.sh 30
```

---

## 🆘 Emergency Contacts

```
Container Won't Start:
  → Check: docker logs liquorpro-sales-prod
  → Try: docker restart liquorpro-sales-prod
  → Rollback: docker tag liquorpro/sales:backup liquorpro/sales:latest

High Error Rate:
  → Check: docker logs --tail 100 | grep -i error
  → Monitor: ./scripts/ocr_metrics_monitor.sh 15
  → Review: Recent changes in git log

Production Issue:
  → Immediate: Check TROUBLESHOOTING_FAQ.md
  → Debug: Enable verbose logging (temporary)
  → Escalate: Team lead / On-call
```

---

## 💡 Pro Tips

```
1. Bookmark this cheat sheet
2. Use bash aliases:
   alias ocr-test='./scripts/ocr_test_runner.sh'
   alias ocr-monitor='./scripts/ocr_metrics_monitor.sh 60'
   alias ocr-logs='sudo docker logs liquorpro-sales-prod'

3. Watch tests while developing:
   watch -n 2 'go test -run TestYourTest ./internal/sales/services'

4. Search all docs:
   grep -ri "keyword" *.md

5. Always monitor after deployment!
```

---

**Print this page and keep it handy!**

**Quick Help**: `cat TROUBLESHOOTING_FAQ.md`
**Full Docs**: `cat BEST_PRACTICES_INDEX.md`

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0

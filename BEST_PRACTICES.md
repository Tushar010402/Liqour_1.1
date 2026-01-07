# OCR Accuracy Improvement - Best Practices Guide

**Purpose**: Maintain high quality, performance, and reliability of the OCR system
**Audience**: Developers, DevOps, QA, Team Leads
**Version**: 1.0.0

---

## 🎯 Overview

This guide provides proven best practices for maintaining and improving the OCR accuracy system. Following these practices ensures:

- ✅ Consistent high accuracy (95%+)
- ✅ Optimal performance and cost efficiency
- ✅ Easy maintenance and debugging
- ✅ Smooth team collaboration
- ✅ Production stability

---

## 📝 Table of Contents

1. [Code Development](#code-development)
2. [Testing](#testing)
3. [Monitoring & Operations](#monitoring--operations)
4. [Performance Optimization](#performance-optimization)
5. [Security & API Usage](#security--api-usage)
6. [Documentation](#documentation)
7. [Deployment](#deployment)
8. [Incident Response](#incident-response)
9. [Team Collaboration](#team-collaboration)
10. [Continuous Improvement](#continuous-improvement)

---

## 💻 Code Development

### General Principles

**✅ DO**:
- Keep functions small (<100 lines, ideally <50)
- Use descriptive variable names (`normalizedBrandName` not `nbr`)
- Add comments explaining "why", not "what"
- Follow existing code patterns and style
- Use constants for magic numbers
- Handle errors explicitly

**❌ DON'T**:
- Create monolithic functions
- Use cryptic abbreviations
- Leave TODO comments without tickets
- Ignore compiler warnings
- Copy-paste code without understanding

### OCR-Specific Best Practices

#### 1. Pattern Matching

**✅ GOOD**:
```go
// Handle common OCR errors: 0→O, 1→I, S→5
size90Patterns := []string{
    `9[0oO]\s*m[\.\s]*l`,  // Matches: 90ml, 9Oml, 9o m.l
    `nip`,                  // Common alias for 90ml
}
```

**❌ BAD**:
```go
// Generic pattern that might match too much
pattern := `.*90.*`
```

**Why**: Specific patterns reduce false positives and are easier to debug.

---

#### 2. Fallback Chains

**✅ GOOD**:
```go
// Try multiple extraction methods in order
if price, ok := extractPriceFromRate(data); ok {
    return price
}
if price, ok := extractPriceFromCalculation(data); ok {
    return price
}
return 0.0  // Clear failure indicator
```

**❌ BAD**:
```go
// Single method with complex logic
price := complexExtractionWithManyConditions(data)
return price  // Unclear if it succeeded
```

**Why**: Fallback chains are easier to test, debug, and extend.

---

#### 3. Validation

**✅ GOOD**:
```go
func validatePriceRange(price float64, receiptType string) bool {
    ranges := map[string]struct{min, max float64}{
        "90ml":  {40, 300},
        "180ml": {80, 500},
        "375ml": {150, 1000},
        "750ml": {300, 3000},
    }

    r, exists := ranges[receiptType]
    if !exists {
        return price >= 50 && price <= 2000  // Default range
    }
    return price >= r.min && price <= r.max
}
```

**❌ BAD**:
```go
func validatePrice(price float64) bool {
    return price > 0  // Too permissive
}
```

**Why**: Specific validation catches data quality issues early.

---

#### 4. Logging

**✅ GOOD**:
```go
fmt.Printf("🔧 [OCR] Fuzzy matched %s using pattern: %s\n", result, pattern)
fmt.Printf("💨 [Cache HIT] '%s' → '%s' (saved API call)\n", input, cached)
fmt.Printf("✅ [Validation] All checks passed for '%s'\n", brand)
```

**❌ BAD**:
```go
fmt.Println("Processing complete")  // No context
log.Debug(data)  // Dumps raw data without explanation
```

**Why**: Structured logging with emojis makes production debugging easy.

---

#### 5. Error Handling

**✅ GOOD**:
```go
normalized, err := client.NormalizeBrandName(ctx, brandText)
if err != nil {
    log.Printf("❌ Brand normalization failed for '%s': %v", brandText, err)
    // Try fallback or return with context
    return fallbackNormalization(brandText), nil
}
```

**❌ BAD**:
```go
normalized, _ := client.NormalizeBrandName(ctx, brandText)
// Silently ignoring errors
```

**Why**: Explicit error handling prevents silent failures.

---

### Code Review Checklist

Before committing changes:

- [ ] Function is <100 lines
- [ ] All variables have clear names
- [ ] Edge cases are handled
- [ ] Errors are logged appropriately
- [ ] Logging includes context (brand name, size, etc.)
- [ ] No magic numbers (use constants)
- [ ] Comments explain complex logic
- [ ] No TODO without tracking ticket

---

## 🧪 Testing

### Test Coverage Standards

**Minimum Requirements**:
- Overall coverage: >80%
- Critical paths: 100%
- New code: >90%
- Bug fixes: Add regression test

### Writing Good Tests

**✅ GOOD - Table-Driven Tests**:
```go
func TestDetectReceiptType(t *testing.T) {
    tests := []struct {
        name     string
        rawText  string
        expected string
    }{
        {"Standard 90ml", "SALE RECEIPT - 90 M.L", "90ml"},
        {"OCR error 9O", "SALE RECEIPT - 9O M.L", "90ml"},
        {"Alias NIP", "SALE RECEIPT - NIP", "90ml"},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := detectReceiptType(tt.rawText)
            if result != tt.expected {
                t.Errorf("Expected %s, got %s", tt.expected, result)
            }
        })
    }
}
```

**❌ BAD**:
```go
func TestDetect(t *testing.T) {
    if detectReceiptType("90ml") != "90ml" {
        t.Error("failed")
    }
    // Only one test case, unclear what failed
}
```

**Why**: Table-driven tests are easier to extend and debug.

---

### Test Organization

**✅ GOOD Structure**:
```
ocr_service_test.go
├── Phase 1 Tests
│   ├── TestDetectReceiptType (13 cases)
│   └── TestJSONRepair (multiple cases)
├── Phase 2 Tests
│   ├── TestValidatePriceRange (15 cases)
│   ├── TestExtractPriceFromRate (10 cases)
│   └── TestDetectMergedRows (4 cases)
└── Phase 3 Tests
    └── TestValidateCrossFields (8 cases)
```

**Why**: Organized tests are easier to maintain and understand.

---

### Before Every Commit

```bash
# 1. Run tests
./scripts/ocr_test_runner.sh

# 2. Check coverage
./scripts/ocr_test_runner.sh --coverage

# 3. Verify no regressions
./scripts/ocr_benchmark.sh
```

---

### When to Write Tests

**ALWAYS write tests for**:
- New features
- Bug fixes (regression tests)
- Refactoring (ensure behavior unchanged)
- Complex logic
- Public APIs

**Examples**:

```go
// Bug fix: Add regression test
func TestBugFix_NegativeQuantityRejection(t *testing.T) {
    // Reproduces bug before fix
    result := validateCrossFields(&ocr.ExtractedBrand{
        Quantity: -5,  // This caused a crash before fix
    })

    // Verify fix
    if result.IsValid {
        t.Error("Negative quantity should be rejected")
    }
}
```

---

## 📊 Monitoring & Operations

### Daily Monitoring Routine

**Morning Check** (2 minutes):
```bash
# 1. Container healthy?
docker ps | grep sales

# 2. Any errors overnight?
docker logs liquorpro-sales-prod --since 12h | grep -i error | wc -l

# 3. Quick verification
./scripts/verify_deployment.sh | tail -5
```

**During Peak Hours** (ongoing):
```bash
# Live monitoring
./scripts/ocr_metrics_monitor.sh 60
```

**End of Day** (2 minutes):
```bash
# Review daily stats
docker logs liquorpro-sales-prod --since 1d | \
  grep -E "Fuzzy|Cache|Validation" | wc -l
```

---

### Metrics to Track

**Daily**:
- Cache hit rate (target: >70%)
- Validation pass rate (target: >90%)
- Critical failures (target: <5%)
- Items processed (trend monitoring)

**Weekly**:
- Average accuracy (target: >95%)
- API cost (should remain ~30% of baseline)
- Manual correction rate (target: <10%)
- Error patterns (look for trends)

**Monthly**:
- Overall system health
- Performance trends
- Cost analysis
- User feedback summary

---

### Alert Thresholds

**🔴 CRITICAL - Immediate Action**:
- Container down
- Error rate >20%
- Critical validation failures >10%
- Cache hit rate <30% (after warm-up)

**🟡 WARNING - Investigate**:
- Cache hit rate <50%
- Validation pass rate <80%
- Error rate >10%
- API response time >3s

**🟢 NORMAL**:
- Cache hit rate >70%
- Validation pass rate >90%
- Error rate <5%
- API response time <1s

---

### Log Analysis Best Practices

**✅ GOOD Queries**:
```bash
# Specific time range
docker logs liquorpro-sales-prod --since "2025-01-15T09:00:00" \
  --until "2025-01-15T10:00:00" | grep ERROR

# Pattern analysis
docker logs liquorpro-sales-prod | \
  grep "Fuzzy matched" | \
  awk -F'pattern:' '{print $2}' | \
  sort | uniq -c | sort -rn

# Performance tracking
docker logs liquorpro-sales-prod --since 1h | \
  grep "API call" | \
  awk '{print $NF}' | \
  awk '{sum+=$1; count++} END {print "Avg:", sum/count "ms"}'
```

**❌ BAD**:
```bash
# Too broad, hard to analyze
docker logs liquorpro-sales-prod | grep ".*"
```

---

## ⚡ Performance Optimization

### Cache Usage

**✅ BEST PRACTICES**:

1. **Warm up cache on startup**:
```go
// Pre-load common brands
commonBrands := []string{"Royal Stag", "Blenders Pride", "8PM Black"}
for _, brand := range commonBrands {
    client.NormalizeBrandName(ctx, brand)
}
```

2. **Monitor cache effectiveness**:
```bash
# Calculate hit rate
HITS=$(docker logs liquorpro-sales-prod --since 1h | grep -c "Cache HIT")
MISSES=$(docker logs liquorpro-sales-prod --since 1h | grep -c "Cache MISS")
echo "Hit rate: $(awk "BEGIN {printf \"%.1f%%\", ($HITS/($HITS+$MISSES))*100}")"
```

3. **Adjust TTL based on usage patterns**:
```go
// If brands change daily: 1 hour TTL ✅
// If brands change weekly: 24 hour TTL might be better
cacheTTL := 1 * time.Hour
```

---

### API Call Optimization

**✅ DO**:
- Batch related operations
- Use cache aggressively
- Implement rate limiting
- Retry with exponential backoff
- Monitor API usage trends

**❌ DON'T**:
- Make unnecessary API calls
- Retry immediately on failure
- Ignore rate limit errors
- Cache forever (memory leak)
- Make calls in tight loops

**Example - Rate Limiting**:
```go
limiter := rate.NewLimiter(rate.Limit(10), 1)  // 10 calls/sec
limiter.Wait(ctx)  // Wait for token before API call
```

---

### Memory Management

**Monitor memory usage**:
```bash
docker stats liquorpro-sales-prod --no-stream
```

**Cache size guidelines**:
- Small cache (<1000 items): ~10-50 MB ✅
- Medium cache (1000-10000): ~50-200 MB ⚠️
- Large cache (>10000): Consider external cache (Redis)

**Cleanup strategy**:
```go
// Current: Cleanup every 15 minutes ✅
// Alternative: Cleanup when size exceeds threshold
if len(cache) > 10000 {
    cleanupExpiredEntries()
}
```

---

## 🔒 Security & API Usage

### API Key Management

**✅ SECURE**:
```go
// Read from environment variable
apiKey := os.Getenv("GEMINI_API_KEY")
if apiKey == "" {
    log.Fatal("GEMINI_API_KEY not set")
}
```

**❌ INSECURE**:
```go
// Hardcoded API key - NEVER DO THIS
apiKey := "AIzaSyAbc123..."
```

---

### Data Privacy

**✅ BEST PRACTICES**:

1. **Don't log sensitive data**:
```go
// GOOD
log.Printf("Processing invoice for brand: %s", brandName)

// BAD - might contain PII
log.Printf("Full invoice data: %+v", invoiceData)
```

2. **Sanitize before sending to Gemini**:
```go
// Remove potential PII before API call
sanitizedText := removePII(rawText)
result := client.ExtractBrand(ctx, sanitizedText)
```

3. **Limit data retention**:
- Keep logs for 30-90 days max
- Archive if needed for compliance
- Delete temporary files promptly

---

### API Usage Limits

**Gemini API Guidelines**:
- Respect rate limits
- Implement exponential backoff
- Monitor quota usage
- Have fallback strategies
- Track costs regularly

**Example - Quota Monitoring**:
```bash
# Track daily API calls
TODAY=$(date +%Y-%m-%d)
docker logs liquorpro-sales-prod --since 1d | \
  grep "Gemini.*API call" | \
  wc -l
echo "API calls on $TODAY: $COUNT"
```

---

## 📖 Documentation

### Code Documentation

**✅ GOOD Comments**:
```go
// fuzzyDetectSize handles common OCR errors where characters
// are misread (e.g., 0→O, 1→I). This is critical because Vision API
// sometimes returns "9O ml" instead of "90 ml" for poor quality images.
func fuzzyDetectSize(text string) string {
    // Try each pattern in order of specificity
    for _, pattern := range size90Patterns {
        if matched, _ := regexp.MatchString(pattern, text); matched {
            return "90ml"
        }
    }
    return ""
}
```

**❌ BAD Comments**:
```go
// Detect size
func detectSize(text string) string {
    // Loop through patterns
    for _, p := range patterns {
        // Check if matches
        if match(p, text) {
            return "90ml"  // Return 90ml
        }
    }
    return ""  // Return empty
}
```

**Why**: Good comments explain context and reasoning, not just what the code does.

---

### Documentation Updates

**ALWAYS update docs when**:
- Adding new features
- Changing behavior
- Fixing bugs
- Modifying APIs
- Updating configuration

**Which docs to update**:

| Change Type | Update These Docs |
|-------------|-------------------|
| New feature | CHANGELOG, README, NEXT_STEPS |
| Bug fix | CHANGELOG, TROUBLESHOOTING_FAQ |
| Config change | README, COMMAND_REFERENCE |
| Performance improvement | CHANGELOG, monitoring guides |
| Breaking change | CHANGELOG, migration guide, README |

---

### Documentation Standards

**✅ GOOD Documentation**:
- Clear purpose statement
- Step-by-step instructions
- Real examples
- Expected outcomes
- Troubleshooting section
- Last updated date

**Example Template**:
```markdown
# Feature Name

**Purpose**: What this does
**When to use**: Specific scenarios
**Prerequisites**: What you need first

## How to Use

1. Step one
   ```bash
   command --example
   ```

2. Step two

## Expected Result

You should see: [description]

## Troubleshooting

If X happens: Try Y

**Last Updated**: 2025-01-15
```

---

## 🚀 Deployment

### Pre-Deployment Checklist

Before deploying changes:

- [ ] All tests passing (`./scripts/ocr_test_runner.sh`)
- [ ] Code reviewed by team member
- [ ] Documentation updated
- [ ] Backward compatible OR migration plan ready
- [ ] Benchmarks show no regressions
- [ ] Monitoring alerts configured
- [ ] Rollback plan documented

---

### Deployment Process

**✅ RECOMMENDED Steps**:

1. **Deploy to staging first**:
```bash
# Build and test in staging
docker-compose -f docker-compose.staging.yml up -d
./scripts/verify_deployment.sh
```

2. **Monitor staging**:
```bash
# Watch for 30 minutes
./scripts/ocr_metrics_monitor.sh 30
```

3. **Deploy to production** (if staging looks good):
```bash
# Build production image
docker-compose -f docker-compose.production.yml build sales

# Deploy with zero downtime
docker-compose -f docker-compose.production.yml up -d --no-deps sales
```

4. **Verify production**:
```bash
./scripts/verify_deployment.sh
./scripts/ocr_metrics_monitor.sh 10  # Quick check
```

5. **Monitor closely for first hour**:
```bash
# Watch for issues
docker logs -f liquorpro-sales-prod | grep -i error
```

---

### Rollback Plan

**If issues occur**:

1. **Quick rollback** (revert to previous image):
```bash
# Use previous known-good image
docker-compose -f docker-compose.production.yml down sales
docker-compose -f docker-compose.production.yml up -d sales:<previous-tag>
```

2. **Verify rollback**:
```bash
./scripts/verify_deployment.sh
```

3. **Document incident**:
- What went wrong
- What was rolled back
- Root cause analysis
- Prevention measures

---

## 🚨 Incident Response

### When Issues Occur

**Severity Levels**:

**P0 - CRITICAL** (Act immediately):
- System down
- Data corruption
- Security breach
- Error rate >50%

**P1 - HIGH** (Fix within 1 hour):
- Performance degraded >50%
- Key feature broken
- Error rate >20%

**P2 - MEDIUM** (Fix within 1 day):
- Non-critical feature broken
- Performance degraded <50%
- Error rate 10-20%

**P3 - LOW** (Fix when convenient):
- Minor bugs
- Cosmetic issues
- Error rate <10%

---

### Incident Response Process

1. **Assess severity** (2 min)
2. **Notify team** (if P0/P1)
3. **Gather information**:
```bash
# Collect logs
docker logs liquorpro-sales-prod --since 1h > incident_logs.txt

# Check metrics
./scripts/ocr_metrics_monitor.sh 5

# Recent changes
git log --since="1 day ago" --oneline
```

4. **Mitigate immediately**:
   - Rollback if recent deploy
   - Disable problematic feature
   - Scale resources if needed

5. **Fix root cause**

6. **Document**:
   - What happened
   - Impact (users affected, duration)
   - Root cause
   - Fix applied
   - Prevention measures

---

### Post-Incident Review

**Within 48 hours, document**:

1. **Timeline**: When issue started/detected/resolved
2. **Root Cause**: What exactly went wrong
3. **Impact**: Number of users, data affected
4. **Resolution**: What fixed it
5. **Prevention**: How to prevent recurrence
6. **Action Items**: Tasks to improve (with owners)

**Example Template**:
```markdown
# Incident Report: [Title]

**Date**: 2025-01-15
**Severity**: P1
**Duration**: 45 minutes

## Summary
[One paragraph describing what happened]

## Timeline
- 09:00: Issue detected
- 09:05: Team notified
- 09:15: Root cause identified
- 09:45: Resolution deployed

## Root Cause
[Technical explanation]

## Resolution
[What fixed it]

## Action Items
1. [Task] - Owner: [Name] - Due: [Date]
2. [Task] - Owner: [Name] - Due: [Date]

## Lessons Learned
[What we learned]
```

---

## 👥 Team Collaboration

### Code Reviews

**Reviewer Checklist**:
- [ ] Code is understandable
- [ ] Tests are adequate
- [ ] No security issues
- [ ] Performance acceptable
- [ ] Documentation updated
- [ ] Follows project conventions
- [ ] Error handling appropriate

**Review Standards**:
- Review within 24 hours
- Be constructive and specific
- Ask questions if unclear
- Suggest alternatives
- Approve when satisfied

---

### Knowledge Sharing

**✅ GOOD Practices**:

1. **Document decisions**:
   - Why we chose this approach
   - Alternatives considered
   - Trade-offs made

2. **Share learnings**:
   - Weekly team updates
   - Document gotchas
   - Share useful tools/scripts

3. **Onboarding**:
   - Maintain onboarding guide
   - Pair program for first week
   - Review documentation together

4. **Runbooks**:
   - Common operations
   - Troubleshooting steps
   - Emergency procedures

---

### Communication

**When to notify team**:

| Event | Notify | How |
|-------|--------|-----|
| Critical incident | Immediately | Phone/Slack |
| Major deployment | 24h advance | Email/Slack |
| Breaking change | 1 week advance | Email + meeting |
| Minor update | After deploy | Slack |
| Bug fix | After deploy | Changelog |

---

## 📈 Continuous Improvement

### Regular Reviews

**Weekly**:
- Review error logs for patterns
- Check performance metrics
- Update documentation if needed
- Plan improvements

**Monthly**:
- Analyze trends
- Review test coverage
- Update dependencies
- Plan refactoring

**Quarterly**:
- Major performance review
- Architecture review
- Technology updates
- Team retrospective

---

### Metrics-Driven Improvement

**Track trends**:
```bash
# Example: Weekly accuracy trend
for week in $(seq 1 4); do
  echo "Week $week:"
  # Calculate accuracy from logs
  # Compare with target (95%)
done
```

**Identify improvement opportunities**:
- Accuracy <95%: Investigate failure patterns
- Cache hit <70%: Review caching strategy
- API costs increasing: Optimize usage
- Error rate rising: Debug root causes

---

### A/B Testing

**When making improvements**:

1. **Baseline**: Measure current performance
2. **Change**: Implement improvement
3. **Compare**: A/B test if possible
4. **Validate**: Run benchmarks
5. **Deploy**: If proven better
6. **Monitor**: Track impact

**Example**:
```bash
# Before change
./scripts/ocr_benchmark.sh > baseline.txt

# After change
./scripts/ocr_benchmark.sh > improved.txt

# Compare
diff baseline.txt improved.txt
```

---

## ✅ Daily Checklist for Developers

### Morning
- [ ] Check container status
- [ ] Review overnight errors
- [ ] Scan team notifications

### Before Coding
- [ ] Pull latest changes
- [ ] Run tests to ensure green
- [ ] Review related docs

### Before Committing
- [ ] Run tests: `./scripts/ocr_test_runner.sh`
- [ ] Check coverage if new code
- [ ] Update relevant docs
- [ ] Verify no debugging code left

### Before Going Home
- [ ] Code reviewed or submitted for review
- [ ] Tests passing on CI
- [ ] Documentation updated
- [ ] Team notified of any issues

---

## 📋 Monthly Health Check

Use this checklist monthly:

### Performance
- [ ] Cache hit rate >70%
- [ ] API costs within budget
- [ ] Processing time stable
- [ ] Memory usage normal

### Quality
- [ ] Accuracy >95%
- [ ] Error rate <5%
- [ ] Test coverage >80%
- [ ] No critical bugs

### Operations
- [ ] Monitoring working
- [ ] Alerts configured
- [ ] Logs manageable size
- [ ] Backups working

### Team
- [ ] Documentation current
- [ ] No knowledge silos
- [ ] Onboarding smooth
- [ ] Runbooks updated

---

## 🎯 Success Indicators

You're doing it right when:

✅ **Code Quality**:
- Functions < 100 lines
- Tests pass reliably
- Coverage > 80%
- No mysterious bugs

✅ **Operations**:
- No surprise outages
- Issues detected early
- Quick recovery from problems
- Predictable performance

✅ **Team**:
- Fast onboarding
- Easy to find information
- Smooth deployments
- Good collaboration

✅ **Users**:
- High satisfaction
- Few error reports
- Accurate results
- Fast processing

---

## 📚 Additional Resources

**Related Documentation**:
- Technical Details: `CHANGELOG_OCR_IMPROVEMENTS.md`
- Operations: `COMMAND_REFERENCE.md`
- Troubleshooting: `TROUBLESHOOTING_FAQ.md`
- Testing: `scripts/README_OCR_TESTING.md`

**External Resources**:
- Go Best Practices: https://go.dev/doc/effective_go
- Testing Best Practices: https://go.dev/blog/testing
- Gemini API Docs: https://ai.google.dev/docs

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0
**Maintained By**: Development Team

---

> **Remember**: Best practices are guidelines, not rigid rules. Use judgment based on context. When in doubt, prioritize: 1) Correctness, 2) Simplicity, 3) Performance, in that order.

**Questions?** Check the FAQ or ask the team!

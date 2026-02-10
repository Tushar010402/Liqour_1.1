# OCR System - Frequently Asked Questions (FAQ)

**Quick Answers to Common Questions**

**Last Updated**: January 15, 2025
**Version**: 1.0.0

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Development](#development)
3. [Testing](#testing)
4. [Deployment](#deployment)
5. [Troubleshooting](#troubleshooting)
6. [Performance](#performance)
7. [Architecture](#architecture)
8. [Best Practices](#best-practices)

---

## Getting Started

### Q: I'm new to the project. Where should I start?

**A**: Follow this quick start path:
1. Read `BEST_PRACTICES_INDEX.md` (10 min)
2. Read `OCR_QUICK_CHEAT_SHEET.md` (10 min)
3. Follow "Your First Day" in `OCR_DEVELOPMENT_GUIDE.md` (4 hours)
4. Review top 5 pitfalls in `COMMON_PITFALLS.md` (30 min)

Total time to productivity: **~4 hours**

---

### Q: What documentation should I read for my role?

**A**: Depends on your role:

**New Developer**:
- BEST_PRACTICES_INDEX.md
- OCR_DEVELOPMENT_GUIDE.md
- OCR_QUICK_CHEAT_SHEET.md

**Code Reviewer**:
- CODE_REVIEW_CHECKLIST.md
- BEST_PRACTICES.md
- COMMON_PITFALLS.md

**Team Lead**:
- ARCHITECTURE.md
- DEVELOPMENT_WORKFLOWS.md
- MONITORING_OBSERVABILITY_GUIDE.md

**DevOps/SRE**:
- DEPLOYMENT_GUIDE.md
- MONITORING_OBSERVABILITY_GUIDE.md
- OCR_TROUBLESHOOTING_GUIDE.md

---

### Q: How do I set up my development environment?

**A**: Follow these steps:

```bash
# 1. Clone the repository
git clone <repository-url>
cd liquorpro

# 2. Install Go (1.21+)
# (See https://go.dev/doc/install)

# 3. Install dependencies
go mod download

# 4. Set up environment variables
cp .env.example .env
# Edit .env with your credentials

# 5. Run tests to verify setup
go test ./internal/sales/services

# 6. Start development server
go run cmd/sales/main.go
```

**See**: `OCR_DEVELOPMENT_GUIDE.md` - "Your First Day" section

---

## Development

### Q: How do I add support for a new product size (e.g., "1L")?

**A**: Add a fuzzy pattern in `detectReceiptType` function:

```go
// In internal/sales/services/ocr.go
func detectReceiptType(rawText string) string {
    textLower := strings.ToLower(rawText)

    // Add new size pattern
    size1LPatterns := []string{
        `1[lI]?\s*l`,           // Handles: 1L, 1l, 1 l
        `1[0oO]{3}\s*m[l1]`,    // Handles: 1000ml, 1O00ml
    }

    for _, pattern := range size1LPatterns {
        if matched, _ := regexp.MatchString(pattern, textLower); matched {
            fmt.Printf("🔧 [OCR] Fuzzy matched 1L using pattern: %s\n", pattern)
            return "1L"
        }
    }

    // ... existing patterns
}
```

Then add tests:
```go
func TestDetect1L(t *testing.T) {
    tests := []string{"1L", "1l", "1 L", "1000ml", "1O00ml"}

    for _, input := range tests {
        result := detectReceiptType(input)
        assert.Equal(t, "1L", result, "Failed for input: %s", input)
    }
}
```

**See**: `OCR_DEVELOPMENT_GUIDE.md` - "Adding a New Fuzzy Pattern"

---

### Q: How do I add a new field to extract (e.g., "alcohol content")?

**A**: Follow these steps:

1. **Update OCRResult struct**:
```go
type ExtractedBrand struct {
    Size         string  `json:"size"`
    BrandName    string  `json:"brand_name"`
    Price        float64 `json:"price"`
    Category     string  `json:"category"`
    AlcoholContent float64 `json:"alcohol_content"`  // NEW
}
```

2. **Add extraction function**:
```go
func extractAlcoholContent(text string) float64 {
    // Pattern: "40% ABV", "40.5%", "80 proof"
    patterns := []string{
        `(\d+\.?\d*)\s*%\s*(?:abv|alc)`,
        `(\d+)\s*proof`,  // Convert proof to ABV (proof/2)
    }

    for _, pattern := range patterns {
        re := regexp.MustCompile(pattern)
        if matches := re.FindStringSubmatch(text); len(matches) > 1 {
            abv, _ := strconv.ParseFloat(matches[1], 64)

            // Convert proof to ABV if needed
            if strings.Contains(pattern, "proof") {
                abv = abv / 2
            }

            return abv
        }
    }

    return 0.0
}
```

3. **Add validation**:
```go
func validateAlcoholContent(abv float64, category string) error {
    if abv < 0 || abv > 100 {
        return fmt.Errorf("invalid ABV: %.2f", abv)
    }

    // Category-specific validation
    if category == "Beer" && abv > 20 {
        return fmt.Errorf("beer ABV too high: %.2f", abv)
    }

    return nil
}
```

4. **Add tests**:
```go
func TestExtractAlcoholContent(t *testing.T) {
    tests := []struct {
        input    string
        expected float64
    }{
        {"40% ABV", 40.0},
        {"40.5%", 40.5},
        {"80 proof", 40.0},
        {"No alcohol info", 0.0},
    }

    for _, tt := range tests {
        result := extractAlcoholContent(tt.input)
        assert.Equal(t, tt.expected, result)
    }
}
```

**See**: `OCR_DEVELOPMENT_GUIDE.md` - "Adding Validation for a New Field"

---

### Q: How do I test my changes locally before pushing?

**A**: Run this checklist:

```bash
# 1. Run unit tests
go test ./internal/sales/services -v

# 2. Run integration tests
go test -run Integration ./...

# 3. Run all tests with coverage
go test -cover ./...

# 4. Check for race conditions
go test -race ./...

# 5. Run linter
golangci-lint run

# 6. Format code
go fmt ./...

# 7. Build to ensure no compilation errors
go build ./cmd/sales

# 8. Test with real invoice (optional)
./scripts/quick_ocr_test.sh
```

**See**: `TESTING_STRATEGY_DEEP_DIVE.md`

---

### Q: What's the difference between the Vision API and Gemini API?

**A**:

**Vision API** (Google Cloud Vision):
- **Purpose**: Optical Character Recognition (OCR)
- **Input**: Image (invoice photo)
- **Output**: Raw text extracted from image
- **Example**: "grey goose 75oml $29.99"

**Gemini API** (Google Generative AI):
- **Purpose**: Brand name normalization
- **Input**: Raw text from OCR
- **Output**: Corrected/normalized brand name
- **Example**: "grey goose" → "Grey Goose"

**Flow**:
```
Invoice Image → [Vision API] → Raw Text → [Gemini API] → Normalized Brand
```

**See**: `ARCHITECTURE.md` - "Service Overview"

---

## Testing

### Q: How do I write a good test?

**A**: Follow the AAA pattern (Arrange-Act-Assert):

```go
func TestDetectSize_OCRError(t *testing.T) {
    // Arrange - Set up test data
    input := "Product 75Oml"  // O instead of 0

    // Act - Execute the function
    result := detectSize(input)

    // Assert - Verify the result
    expected := "750ml"
    if result != expected {
        t.Errorf("Expected %s, got %s", expected, result)
    }
}
```

**Best Practices**:
- One test per scenario
- Clear test names describing what's being tested
- Use table-driven tests for multiple inputs
- Test both success and failure cases
- Don't test implementation details

**See**: `TESTING_STRATEGY_DEEP_DIVE.md` - "Unit Testing Patterns"

---

### Q: Should I mock external APIs in tests?

**A**: **Yes, for unit tests**. **No, for integration tests**.

**Unit Tests** (fast, isolated):
```go
mockVision := &MockVisionAPI{
    Response: "Test text",
}
result := extractOCR(mockVision, testImage)
```

**Integration Tests** (realistic, slower):
```go
realVisionAPI := setupRealVisionAPI()
result := extractOCR(realVisionAPI, testImage)
```

**Rule of thumb**:
- Unit tests: Mock everything external
- Integration tests: Use real services
- E2E tests: Use production-like environment

**See**: `TESTING_STRATEGY_DEEP_DIVE.md` - "Testing External APIs"

---

### Q: How do I run only specific tests?

**A**: Use the `-run` flag:

```bash
# Run specific test by name
go test -run TestDetectSize ./internal/sales/services

# Run all tests matching pattern
go test -run ".*Size.*" ./internal/sales/services

# Run tests in specific package
go test ./internal/sales/services

# Run with verbose output
go test -v -run TestDetectSize ./internal/sales/services

# Skip long-running tests
go test -short ./...
```

**See**: `OCR_QUICK_CHEAT_SHEET.md` - "Top 10 Essential Commands"

---

## Deployment

### Q: How do I deploy my changes to production?

**A**: Follow the deployment workflow:

1. **Create Pull Request**
2. **Code Review** - Get approval
3. **Merge to main**
4. **Build Docker image**:
   ```bash
   sudo -E bash -c "set -a; source .env.production; docker compose -f docker-compose.production.yml build sales"
   ```
5. **Deploy**:
   ```bash
   sudo -E bash -c "set -a; source .env.production; docker compose -f docker-compose.production.yml up -d --no-deps sales"
   ```
6. **Verify deployment**:
   ```bash
   ./scripts/verify_deployment.sh
   ```
7. **Monitor**:
   ```bash
   ./scripts/ocr_metrics_monitor.sh 60
   ```

**See**: `DEPLOYMENT_GUIDE.md` and `DEVELOPMENT_WORKFLOWS.md` - "Deployment Workflow"

---

### Q: How do I rollback a bad deployment?

**A**: Quick rollback procedure:

```bash
# 1. Identify last good version
git log --oneline -10

# 2. Rollback to that version
./scripts/rollback.sh v1.0.50

# 3. Verify rollback worked
./scripts/verify_deployment.sh

# 4. Check metrics
./scripts/ocr_metrics_monitor.sh 10
```

**Or manually**:
```bash
# Stop current version
sudo -E bash -c "docker compose -f docker-compose.production.yml stop sales"

# Tag rollback in git
git tag rollback-$(date +%Y%m%d-%H%M%S)

# Checkout previous version
git checkout <previous-commit-hash>

# Rebuild and deploy
sudo -E bash -c "set -a; source .env.production; docker compose -f docker-compose.production.yml build sales"
sudo -E bash -c "set -a; source .env.production; docker compose -f docker-compose.production.yml up -d sales"
```

**See**: `DEVELOPMENT_WORKFLOWS.md` - "Deployment Workflow" - Rollback section

---

### Q: Where can I check if my deployment was successful?

**A**: Check multiple sources:

1. **Health endpoint**:
   ```bash
   curl https://api.liquorpro.com/health
   ```

2. **Verification script**:
   ```bash
   ./scripts/verify_deployment.sh
   ```

3. **Docker logs**:
   ```bash
   sudo docker logs liquorpro-sales-prod --tail 50
   ```

4. **Metrics**:
   ```bash
   ./scripts/ocr_metrics_monitor.sh 5
   ```

5. **Test API endpoint**:
   ```bash
   curl -H "Authorization: Bearer $TOKEN" \
     https://api.liquorpro.com/api/ocr/batch/sessions
   ```

**See**: `DEPLOYMENT_GUIDE.md` - "Post-Deployment Verification"

---

## Troubleshooting

### Q: OCR is returning empty results. What should I check?

**A**: Follow this diagnostic process:

```bash
# 1. Check service health
curl https://api.liquorpro.com/health

# 2. Check recent logs for errors
sudo docker logs liquorpro-sales-prod --tail 100 | grep -i error

# 3. Check Vision API connectivity
sudo docker exec liquorpro-sales-prod curl -I https://vision.googleapis.com

# 4. Test with a simple image
./scripts/quick_ocr_test.sh

# 5. Check environment variables
sudo docker exec liquorpro-sales-prod env | grep -E "(GEMINI|GOOGLE|VISION)"
```

**Common Causes**:
- Vision API credentials missing or invalid
- Network connectivity issue
- Image format not supported
- Rate limit exceeded

**See**: `OCR_TROUBLESHOOTING_GUIDE.md` - "Quick Diagnostics"

---

### Q: The cache isn't working. How do I debug it?

**A**: Debug cache issues:

```bash
# 1. Check Redis connection
docker exec liquorpro-redis-prod redis-cli ping
# Expected: PONG

# 2. Check cache keys
docker exec liquorpro-redis-prod redis-cli keys "ocr:*"

# 3. Check metrics
./scripts/ocr_metrics_monitor.sh 5 | grep "cache"

# 4. Test cache manually
docker exec liquorpro-redis-prod redis-cli
> SET test "value"
> GET test
> TTL test
```

**Common Issues**:
- Redis not running
- Connection credentials wrong
- Cache key generation inconsistent
- TTL too short

**See**: `OCR_TROUBLESHOOTING_GUIDE.md` - "Cache Issues"

---

### Q: Tests are failing intermittently. What's wrong?

**A**: Intermittent test failures usually indicate:

1. **Race Conditions**:
   ```bash
   # Run with race detector
   go test -race ./internal/sales/services
   ```

2. **Test Data Pollution**:
   ```go
   // Add cleanup
   t.Cleanup(func() {
       cleanupTestData()
   })
   ```

3. **Non-Deterministic Behavior**:
   - Check for random number generation without seed
   - Check for time-dependent logic
   - Check for map iteration (order is random)

4. **External Dependencies**:
   - Mock external APIs
   - Use test doubles

**See**: `OCR_TROUBLESHOOTING_GUIDE.md` - "Testing Issues"

---

## Performance

### Q: OCR processing is too slow. How can I speed it up?

**A**: Try these optimizations in order:

1. **Enable Caching** (biggest impact):
   ```go
   // Cache OCR results by image hash
   result, cached := getFromCache(imageHash)
   if cached {
       return result  // 10-100x faster
   }
   ```

2. **Optimize Images**:
   ```go
   // Resize large images before sending to Vision API
   optimizedImage := resizeImage(imageData, maxWidth=2000)
   ```

3. **Parallel Processing**:
   ```go
   // Process multiple images concurrently
   var wg sync.WaitGroup
   semaphore := make(chan struct{}, 5)  // Max 5 concurrent

   for _, image := range images {
       wg.Add(1)
       go func(img []byte) {
           defer wg.Done()
           semaphore <- struct{}{}
           defer func() { <-semaphore }()

           processOCR(img)
       }(image)
   }
   wg.Wait()
   ```

4. **Add Timeouts**:
   ```go
   ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
   defer cancel()
   ```

**See**: `OCR_TROUBLESHOOTING_GUIDE.md` - "Performance Issues"

---

### Q: What's the expected performance?

**A**: Performance targets:

| Metric | Target | Acceptable | Poor |
|--------|--------|------------|------|
| Success Rate | >95% | >90% | <90% |
| P50 Latency | <1s | <2s | >2s |
| P95 Latency | <2s | <5s | >5s |
| Cache Hit Rate | >70% | >50% | <50% |
| Field Extraction | >90% | >85% | <85% |

**To check current performance**:
```bash
./scripts/ocr_metrics_monitor.sh 60
```

**See**: `MONITORING_OBSERVABILITY_GUIDE.md` - "Key Metrics"

---

### Q: How do I benchmark my code changes?

**A**: Use Go's benchmarking tools:

```go
func BenchmarkDetectSize(b *testing.B) {
    input := "Product 750ml"

    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        _ = detectSize(input)
    }
}
```

Run benchmarks:
```bash
# Run all benchmarks
go test -bench=. ./internal/sales/services

# Run specific benchmark
go test -bench=BenchmarkDetectSize ./internal/sales/services

# With memory allocation stats
go test -bench=. -benchmem ./internal/sales/services

# Compare before/after
go test -bench=. -benchmem > before.txt
# Make changes...
go test -bench=. -benchmem > after.txt
benchcmp before.txt after.txt
```

**See**: `TESTING_STRATEGY_DEEP_DIVE.md` - "Performance Testing"

---

## Architecture

### Q: How does the OCR system work end-to-end?

**A**: Here's the complete flow:

```
1. User uploads invoice image → API Gateway

2. API Gateway forwards to Sales Service

3. Sales Service:
   ├─ Check cache (Redis)
   │  └─ If cached: Return immediately
   │
   ├─ Call Vision API (Google Cloud Vision)
   │  └─ Extract raw text from image
   │
   ├─ Parse text locally (Go)
   │  ├─ Detect size (fuzzy patterns)
   │  ├─ Extract brand name (regex)
   │  ├─ Extract price (parsing logic)
   │  └─ Extract category (keywords)
   │
   ├─ Call Gemini API (Google Generative AI)
   │  └─ Normalize brand name
   │
   ├─ Validate extracted data
   │  ├─ Required fields present?
   │  ├─ Cross-field consistency?
   │  └─ Reasonable values?
   │
   ├─ Store in database (PostgreSQL)
   │
   ├─ Cache result (Redis, 1-hour TTL)
   │
   └─ Return result to user

4. Response includes:
   - Extracted fields (size, brand, price, category)
   - Confidence scores
   - Processing time
```

**See**: `ARCHITECTURE.md` - "Data Flow"

---

### Q: Why do we use both Vision API and Gemini API?

**A**: They serve different purposes:

**Vision API**:
- **Specialized** for OCR (extracting text from images)
- **Fast** and accurate for text detection
- **Cannot** understand or normalize text

**Gemini API**:
- **Specialized** for language understanding
- **Can** normalize brand names ("grey goose" → "Grey Goose")
- **Cannot** process images directly

**Together**: Vision handles image→text, Gemini handles text→normalized text.

**Alternative considered**: Using only Gemini with vision capabilities
**Why not**: More expensive, slower, less accurate for pure OCR

**See**: `ARCHITECTURE.md` - "External Services"

---

### Q: Where is caching used and why?

**A**: Caching is used in 3 places:

1. **OCR Results Cache** (Redis):
   - **What**: Complete OCR extraction results
   - **Key**: SHA256 hash of image
   - **TTL**: 1 hour
   - **Why**: Same invoice uploaded multiple times (common in testing)

2. **Brand Normalization Cache** (In-memory):
   - **What**: Gemini API responses
   - **Key**: Raw brand name
   - **TTL**: 1 hour
   - **Why**: Reduce Gemini API calls (expensive)

3. **Size Detection Cache** (In-memory):
   - **What**: Detected sizes from header
   - **Key**: Header text
   - **TTL**: 1 hour
   - **Why**: Same receipt type processed repeatedly

**Impact**: 70%+ cache hit rate = 3-10x faster response times

**See**: `ARCHITECTURE.md` - "Caching Strategy"

---

## Best Practices

### Q: What are the most important best practices?

**A**: Top 10 must-follow practices:

1. **Always use fuzzy patterns** for OCR (handles 0→O, 1→l, etc.)
2. **Add cross-field validation** (size/price consistency)
3. **Implement proper error handling** (never swallow errors silently)
4. **Log with context** (request ID, processing time, fields extracted)
5. **Write tests first** (TDD approach)
6. **Use thread-safe caching** (sync.RWMutex)
7. **Add timeouts to external APIs** (prevent hanging)
8. **Validate input data** (don't trust OCR 100%)
9. **Monitor production metrics** (success rate, latency, errors)
10. **Document complex logic** (future you will thank you)

**See**: `BEST_PRACTICES.md`

---

### Q: What should I never do in OCR code?

**A**: Top 10 things to avoid:

1. ❌ **Trust OCR 100%** - Always validate extracted data
2. ❌ **Use exact string matching** - Use fuzzy patterns
3. ❌ **Ignore empty strings** - Distinguish from nil
4. ❌ **Skip error handling** - Always handle errors explicitly
5. ❌ **Hardcode sizes/brands** - Use configurable patterns
6. ❌ **Access cache without mutex** - Race conditions guaranteed
7. ❌ **Skip tests** - Tests catch bugs before production
8. ❌ **Log sensitive data** - API keys, full images
9. ❌ **Deploy without verification** - Always verify first
10. ❌ **Forget to document** - Code without docs is legacy code

**See**: `COMMON_PITFALLS.md`

---

### Q: How often should I commit my code?

**A**: Commit **frequently** with **meaningful messages**:

**Good Practice**:
```bash
# Commit after each logical change
git add internal/sales/services/ocr.go
git commit -m "Add fuzzy pattern for 1L size detection"

git add internal/sales/services/ocr_test.go
git commit -m "Add tests for 1L size detection"
```

**Bad Practice**:
```bash
# One large commit at end of day
git add .
git commit -m "Fixed stuff"
```

**Commit Frequency**: Every 30-60 minutes or after completing a subtask

**See**: `DEVELOPMENT_WORKFLOWS.md` - "Daily Development Workflow"

---

### Q: When should I ask for help?

**A**: Ask for help when:

1. **Stuck for >30 minutes** - Don't waste time
2. **About to make architectural decision** - Get team buy-in
3. **Not sure about security implications** - Better safe than sorry
4. **Tests failing and you don't know why** - Fresh eyes help
5. **Production incident** - Two heads better than one

**Where to ask**:
- Slack #liquorpro-dev channel
- Tag relevant team member in PR
- Schedule quick call if urgent

**See**: `BEST_PRACTICES_INDEX.md` - "Getting Help"

---

## Quick Reference

### Most Useful Commands

```bash
# Health check
curl https://api.liquorpro.com/health

# Run all tests
go test ./internal/sales/services

# Quick OCR test
./scripts/quick_ocr_test.sh

# Monitor production
./scripts/ocr_metrics_monitor.sh 60

# View logs
sudo docker logs liquorpro-sales-prod --tail 100 --follow

# Deploy
./scripts/verify_deployment.sh
```

### Most Useful Files

```
OCR_QUICK_CHEAT_SHEET.md      - Daily reference
OCR_TROUBLESHOOTING_GUIDE.md  - When things break
CODE_REVIEW_CHECKLIST.md      - Before submitting PR
BEST_PRACTICES.md             - When in doubt
```

### Most Common Patterns

```go
// Fuzzy pattern
pattern := `75[0oO]\s*m[l1]`

// Table-driven test
tests := []struct{name, input, expected string}{...}

// Thread-safe cache
mutex.RLock()
defer mutex.RUnlock()

// Timeout
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
```

---

## Still Have Questions?

1. **Search documentation**:
   ```bash
   grep -r "your question" *.md
   ```

2. **Check related guides**:
   - Troubleshooting → `OCR_TROUBLESHOOTING_GUIDE.md`
   - Testing → `TESTING_STRATEGY_DEEP_DIVE.md`
   - Deployment → `DEPLOYMENT_GUIDE.md`
   - Monitoring → `MONITORING_OBSERVABILITY_GUIDE.md`

3. **Ask the team**:
   - Slack #liquorpro-dev
   - Create GitHub discussion
   - Ask in daily standup

4. **Update this FAQ**:
   - If you figured out something useful, add it here!
   - Keep documentation up to date

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0
**Maintained by**: OCR Development Team

**Contribute**: If you found a question missing from this FAQ, please add it!

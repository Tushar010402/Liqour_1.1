# OCR Troubleshooting Guide

**Quick Problem-Solution Reference for Common OCR Issues**

**Reading Time**: 15 minutes
**Last Updated**: January 15, 2025
**Difficulty**: Beginner to Intermediate

---

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Extraction Issues](#extraction-issues)
3. [Performance Issues](#performance-issues)
4. [API Integration Issues](#api-integration-issues)
5. [Data Quality Issues](#data-quality-issues)
6. [Deployment Issues](#deployment-issues)
7. [Cache Issues](#cache-issues)
8. [Testing Issues](#testing-issues)
9. [Emergency Procedures](#emergency-procedures)

---

## Quick Diagnostics

### First Steps for Any OCR Issue

```bash
# 1. Check service health
curl https://api.liquorpro.com/health
# Expected: {"status": "healthy"}

# 2. Check recent logs
sudo docker logs liquorpro-sales-prod --tail 100 | grep -i error

# 3. Check metrics
./scripts/ocr_metrics_monitor.sh 5

# 4. Verify deployment
./scripts/verify_deployment.sh

# 5. Run quick test
./scripts/quick_ocr_test.sh
```

### Diagnostic Decision Tree

```
Is OCR working at all?
├─ NO → Check "API Integration Issues" section
└─ YES → Is accuracy low?
    ├─ YES → Check "Data Quality Issues" section
    └─ NO → Is it slow?
        ├─ YES → Check "Performance Issues" section
        └─ NO → Check "Extraction Issues" section
```

---

## Extraction Issues

### Issue 1: Missing Size Field

**Symptoms**:
- OCR succeeds but `size` field is empty
- Logs show: "Size field missing"
- Extraction rate <90%

**Quick Check**:
```bash
# Check logs for size detection
sudo docker logs liquorpro-sales-prod | grep "Size field missing" | wc -l
```

**Common Causes**:
1. Size only in header, not in item rows
2. OCR misreading size pattern (750ml → 75Oml)
3. Size in unexpected format (7.5dl instead of 750ml)

**Solutions**:

```go
// Solution 1: Add header parsing
func detectReceiptType(rawText string) string {
    // Check header first
    headerLines := strings.Split(rawText, "\n")[:3]  // First 3 lines
    for _, line := range headerLines {
        if size := extractSizePattern(line); size != "" {
            return size
        }
    }
    return "unknown"
}

// Solution 2: Add fuzzy pattern for common OCR error
sizePatterns := []string{
    `75[0oO]\s*m[l1]`,      // Handles 750ml, 75Oml, 75Om1
    `7[5sS][0oO]\s*m[l1]`,  // Handles 7S0ml, 7sOml
}

// Solution 3: Add size inference from price
func inferSizeFromPrice(price float64) string {
    switch {
    case price < 15:
        return "375ml"
    case price < 35:
        return "750ml"
    case price < 60:
        return "1175ml"
    default:
        return ""
    }
}
```

**Verification**:
```bash
# Run tests
go test -run TestSizeDetection ./internal/sales/services

# Check improvement
./scripts/ocr_metrics_monitor.sh 10 | grep "Size extraction"
```

---

### Issue 2: Brand Name Incorrectly Normalized

**Symptoms**:
- Brand name extracted but wrong after normalization
- Example: "Grey Goose" → "Gray Goose"
- Gemini API returning unexpected results

**Quick Check**:
```bash
# Check Gemini API logs
sudo docker logs liquorpro-sales-prod | grep "Gemini API" | tail -20
```

**Common Causes**:
1. Gemini API interpreting brand name as generic term
2. OCR text too noisy for accurate normalization
3. Missing context in prompt to Gemini

**Solutions**:

```go
// Solution 1: Improve Gemini prompt with context
func normalizeBrandName(rawName string, category string, size string) string {
    prompt := fmt.Sprintf(`
Normalize this liquor brand name to its official spelling.

Brand from OCR: %s
Category: %s
Size: %s

Return ONLY the official brand name, nothing else.
If the brand is well-known, use the official spelling.
Examples: "Grey Goose" (not "Gray Goose"), "Johnnie Walker" (not "Johnny Walker")
`, rawName, category, size)

    return callGeminiAPI(prompt)
}

// Solution 2: Add brand name cache with manual overrides
var brandOverrides = map[string]string{
    "gray goose":     "Grey Goose",
    "johnny walker":  "Johnnie Walker",
    "jack daniels":   "Jack Daniel's",
}

func normalizeBrandName(rawName string) string {
    normalized := strings.ToLower(strings.TrimSpace(rawName))

    // Check overrides first
    if override, exists := brandOverrides[normalized]; exists {
        return override
    }

    // Fall back to Gemini API
    return callGeminiAPI(rawName)
}

// Solution 3: Add confidence scoring
func normalizeBrandNameWithConfidence(rawName string) (string, float64) {
    normalized := callGeminiAPI(rawName)

    // Calculate confidence based on edit distance
    confidence := 1.0 - (float64(levenshteinDistance(rawName, normalized)) / float64(len(rawName)))

    if confidence < 0.7 {
        fmt.Printf("⚠️ Low confidence normalization: %s → %s (%.2f)\n",
            rawName, normalized, confidence)
    }

    return normalized, confidence
}
```

**Verification**:
```bash
# Test specific brand
curl -X POST "http://localhost:8092/api/ocr/test-normalize" \
  -d '{"brand": "Gray Goose"}'

# Expected: "Grey Goose"
```

---

### Issue 3: Price Extraction Incorrect

**Symptoms**:
- Price field extracted but value is wrong
- Common errors: $12.34 → 1234, $1,234.56 → 123456
- Decimal point issues

**Quick Check**:
```bash
# Check for price validation failures
sudo docker logs liquorpro-sales-prod | grep "Invalid price" | tail -20
```

**Common Causes**:
1. Comma/period parsing issues (different locales)
2. Currency symbol not stripped
3. OCR misreading decimal point

**Solutions**:

```go
// Solution 1: Robust price parsing
func parsePrice(rawPrice string) (float64, error) {
    // Remove currency symbols and whitespace
    cleaned := strings.TrimSpace(rawPrice)
    cleaned = strings.ReplaceAll(cleaned, "$", "")
    cleaned = strings.ReplaceAll(cleaned, "€", "")
    cleaned = strings.ReplaceAll(cleaned, "£", "")

    // Handle comma as thousand separator
    if strings.Count(cleaned, ",") == 1 && strings.Count(cleaned, ".") == 1 {
        // Format: 1,234.56
        cleaned = strings.ReplaceAll(cleaned, ",", "")
    } else if strings.Count(cleaned, ",") == 1 && !strings.Contains(cleaned, ".") {
        // Could be 1,234 or 12,34 (European)
        parts := strings.Split(cleaned, ",")
        if len(parts[0]) > 2 {
            // American: 1,234 → 1234
            cleaned = strings.ReplaceAll(cleaned, ",", "")
        } else {
            // European: 12,34 → 12.34
            cleaned = strings.ReplaceAll(cleaned, ",", ".")
        }
    }

    price, err := strconv.ParseFloat(cleaned, 64)
    if err != nil {
        return 0, fmt.Errorf("failed to parse price %s: %w", rawPrice, err)
    }

    return price, nil
}

// Solution 2: Add OCR error correction for prices
func correctPriceOCRErrors(rawPrice string) string {
    // Common OCR errors in prices
    corrections := map[string]string{
        "S": "5",  // S → 5
        "O": "0",  // O → 0
        "I": "1",  // I → 1
        "l": "1",  // l → 1
    }

    corrected := rawPrice
    for wrong, right := range corrections {
        corrected = strings.ReplaceAll(corrected, wrong, right)
    }

    return corrected
}

// Solution 3: Add price validation
func validatePrice(price float64, category string) error {
    if price <= 0 {
        return fmt.Errorf("price must be positive, got %.2f", price)
    }

    // Category-specific validation
    maxPrice := 500.0
    if category == "Wine" {
        maxPrice = 1000.0  // Premium wines can be expensive
    }

    if price > maxPrice {
        return fmt.Errorf("price %.2f exceeds max for category %s (%.2f)",
            price, category, maxPrice)
    }

    return nil
}
```

**Verification**:
```bash
# Test price parsing
go test -run TestParsePriceEdgeCases ./internal/sales/services
```

---

### Issue 4: Quantity Field Always Zero

**Symptoms**:
- Quantity field extracted as 0 or missing
- Items have price and size but no quantity

**Quick Check**:
```bash
# Check extraction logs
sudo docker logs liquorpro-sales-prod | grep "quantity" -i | tail -20
```

**Common Causes**:
1. Quantity not explicitly in receipt text
2. Quantity column not detected
3. Defaulting to 0 instead of 1

**Solutions**:

```go
// Solution 1: Default to 1 if not found
func extractQuantity(text string) int {
    // Try to extract quantity
    qtyPattern := regexp.MustCompile(`(?i)qty[\s:]*(\d+)`)
    if matches := qtyPattern.FindStringSubmatch(text); len(matches) > 1 {
        qty, _ := strconv.Atoi(matches[1])
        return qty
    }

    // Default to 1 (most common case)
    return 1
}

// Solution 2: Infer from total/price
func inferQuantity(itemPrice, totalPrice float64) int {
    if itemPrice <= 0 {
        return 1
    }

    qty := int(math.Round(totalPrice / itemPrice))

    // Sanity check
    if qty < 1 || qty > 100 {
        return 1
    }

    return qty
}
```

---

## Performance Issues

### Issue 5: OCR Processing Too Slow

**Symptoms**:
- API response time >5 seconds
- Logs show slow processing times
- Users complaining about delays

**Quick Check**:
```bash
# Check average processing time
sudo docker logs liquorpro-sales-prod | grep "Processing time" | tail -50

# Check if Vision API is slow
sudo docker logs liquorpro-sales-prod | grep "Vision API took" | tail -20
```

**Common Causes**:
1. Large image files not optimized
2. No caching of repeated requests
3. Sequential processing instead of parallel
4. External API timeouts

**Solutions**:

```go
// Solution 1: Add image optimization
func optimizeImage(imageData []byte) []byte {
    img, _, err := image.Decode(bytes.NewReader(imageData))
    if err != nil {
        return imageData  // Return original if decode fails
    }

    // Resize if too large (OCR works fine with smaller images)
    const maxWidth = 2000
    bounds := img.Bounds()
    if bounds.Dx() > maxWidth {
        ratio := float64(maxWidth) / float64(bounds.Dx())
        newHeight := int(float64(bounds.Dy()) * ratio)
        img = resize.Resize(uint(maxWidth), uint(newHeight), img, resize.Lanczos3)
    }

    // Re-encode
    var buf bytes.Buffer
    jpeg.Encode(&buf, img, &jpeg.Options{Quality: 85})
    return buf.Bytes()
}

// Solution 2: Add parallel processing
func processInvoicesBatch(images [][]byte) []OCRResult {
    var wg sync.WaitGroup
    results := make([]OCRResult, len(images))

    // Process up to 5 images in parallel
    semaphore := make(chan struct{}, 5)

    for i, img := range images {
        wg.Add(1)
        go func(index int, imageData []byte) {
            defer wg.Done()

            semaphore <- struct{}{}        // Acquire
            defer func() { <-semaphore }() // Release

            results[index] = processOCR(imageData)
        }(i, img)
    }

    wg.Wait()
    return results
}

// Solution 3: Add response caching
type CachedOCRResult struct {
    Result    OCRResult
    Timestamp time.Time
}

var ocrCache = sync.Map{}

func processOCRWithCache(imageData []byte) OCRResult {
    // Generate hash of image
    hash := sha256.Sum256(imageData)
    cacheKey := hex.EncodeToString(hash[:])

    // Check cache
    if cached, ok := ocrCache.Load(cacheKey); ok {
        cachedResult := cached.(CachedOCRResult)
        if time.Since(cachedResult.Timestamp) < 1*time.Hour {
            fmt.Println("🎯 Cache hit for OCR result")
            return cachedResult.Result
        }
    }

    // Process and cache
    result := processOCR(imageData)
    ocrCache.Store(cacheKey, CachedOCRResult{
        Result:    result,
        Timestamp: time.Now(),
    })

    return result
}

// Solution 4: Add timeout to external API calls
func callVisionAPIWithTimeout(imageData []byte) (*vision.AnnotateImageResponse, error) {
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    resultChan := make(chan *vision.AnnotateImageResponse, 1)
    errChan := make(chan error, 1)

    go func() {
        result, err := visionClient.DetectText(ctx, imageData)
        if err != nil {
            errChan <- err
            return
        }
        resultChan <- result
    }()

    select {
    case result := <-resultChan:
        return result, nil
    case err := <-errChan:
        return nil, err
    case <-ctx.Done():
        return nil, fmt.Errorf("Vision API timeout after 5s")
    }
}
```

**Verification**:
```bash
# Benchmark before/after
go test -bench=BenchmarkOCRProcessing -benchtime=10s

# Monitor in production
./scripts/ocr_metrics_monitor.sh 60
```

---

### Issue 6: High Memory Usage

**Symptoms**:
- Container memory usage >80%
- OOM (Out of Memory) kills
- Logs show memory pressure

**Quick Check**:
```bash
# Check container memory
docker stats liquorpro-sales-prod --no-stream

# Check for memory leaks
sudo docker logs liquorpro-sales-prod | grep "memory" -i
```

**Common Causes**:
1. Image data not being garbage collected
2. Cache growing unbounded
3. Goroutine leaks
4. Large response objects held in memory

**Solutions**:

```go
// Solution 1: Implement LRU cache with max size
type LRUCache struct {
    maxSize int
    cache   *lru.Cache
}

func NewLRUCache(maxSize int) *LRUCache {
    cache, _ := lru.New(maxSize)
    return &LRUCache{
        maxSize: maxSize,
        cache:   cache,
    }
}

func (c *LRUCache) Set(key string, value interface{}) {
    c.cache.Add(key, value)
}

func (c *LRUCache) Get(key string) (interface{}, bool) {
    return c.cache.Get(key)
}

// Solution 2: Clear image data after processing
func processOCRSafe(imageData []byte) OCRResult {
    // Make a copy for processing
    imageCopy := make([]byte, len(imageData))
    copy(imageCopy, imageData)

    // Process
    result := processOCR(imageCopy)

    // Clear the copy
    imageCopy = nil
    runtime.GC()

    return result
}

// Solution 3: Add cache eviction
func startCacheEviction() {
    ticker := time.NewTicker(10 * time.Minute)
    go func() {
        for range ticker.C {
            evictOldCacheEntries()
        }
    }()
}

func evictOldCacheEntries() {
    ocrCache.Range(func(key, value interface{}) bool {
        cached := value.(CachedOCRResult)
        if time.Since(cached.Timestamp) > 1*time.Hour {
            ocrCache.Delete(key)
            fmt.Printf("🗑️ Evicted cache entry: %v\n", key)
        }
        return true
    })
}

// Solution 4: Stream large responses instead of buffering
func streamOCRResults(w http.ResponseWriter, results []OCRResult) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusOK)

    encoder := json.NewEncoder(w)
    encoder.Encode(map[string]string{"status": "success"})

    for _, result := range results {
        encoder.Encode(result)
        w.(http.Flusher).Flush()  // Send immediately
    }
}
```

**Verification**:
```bash
# Monitor memory over time
watch -n 5 'docker stats liquorpro-sales-prod --no-stream'

# Profile memory
go tool pprof http://localhost:6060/debug/pprof/heap
```

---

## API Integration Issues

### Issue 7: Vision API Returning Errors

**Symptoms**:
- OCR completely failing
- Logs show "Vision API error"
- Status code 4xx or 5xx from Vision API

**Quick Check**:
```bash
# Check Vision API errors
sudo docker logs liquorpro-sales-prod | grep "Vision API" | grep -i error

# Test API credentials
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  https://vision.googleapis.com/v1/images:annotate
```

**Common Causes**:
1. Invalid API credentials
2. API quota exceeded
3. API key expired
4. Network connectivity issues
5. Invalid image format

**Solutions**:

```go
// Solution 1: Add retry logic with exponential backoff
func callVisionAPIWithRetry(imageData []byte, maxRetries int) (*vision.AnnotateImageResponse, error) {
    var lastErr error

    for attempt := 0; attempt < maxRetries; attempt++ {
        response, err := callVisionAPI(imageData)

        if err == nil {
            return response, nil
        }

        lastErr = err

        // Check if error is retryable
        if !isRetryableError(err) {
            return nil, fmt.Errorf("non-retryable error: %w", err)
        }

        // Exponential backoff: 1s, 2s, 4s, 8s
        backoff := time.Duration(1<<attempt) * time.Second
        fmt.Printf("⚠️ Vision API attempt %d failed, retrying in %v: %v\n",
            attempt+1, backoff, err)
        time.Sleep(backoff)
    }

    return nil, fmt.Errorf("Vision API failed after %d attempts: %w", maxRetries, lastErr)
}

func isRetryableError(err error) bool {
    // Retry on temporary network errors and 5xx status codes
    if strings.Contains(err.Error(), "timeout") ||
       strings.Contains(err.Error(), "connection refused") ||
       strings.Contains(err.Error(), "503") ||
       strings.Contains(err.Error(), "504") {
        return true
    }
    return false
}

// Solution 2: Validate API credentials on startup
func validateVisionAPICredentials() error {
    ctx := context.Background()
    client, err := vision.NewImageAnnotatorClient(ctx)
    if err != nil {
        return fmt.Errorf("failed to create Vision API client: %w", err)
    }
    defer client.Close()

    // Test with a small dummy image
    dummyImage := createDummyImage()
    _, err = client.DetectText(ctx, dummyImage, nil)

    if err != nil {
        return fmt.Errorf("Vision API credentials invalid: %w", err)
    }

    fmt.Println("✅ Vision API credentials validated")
    return nil
}

// Solution 3: Add circuit breaker for API
type CircuitBreaker struct {
    maxFailures  int
    resetTimeout time.Duration
    failures     int
    lastFailTime time.Time
    state        string  // "closed", "open", "half-open"
    mutex        sync.RWMutex
}

func (cb *CircuitBreaker) Call(fn func() error) error {
    cb.mutex.Lock()
    defer cb.mutex.Unlock()

    if cb.state == "open" {
        if time.Since(cb.lastFailTime) > cb.resetTimeout {
            cb.state = "half-open"
            cb.failures = 0
        } else {
            return fmt.Errorf("circuit breaker open, skipping Vision API call")
        }
    }

    err := fn()

    if err != nil {
        cb.failures++
        cb.lastFailTime = time.Now()
        if cb.failures >= cb.maxFailures {
            cb.state = "open"
            fmt.Printf("🔴 Circuit breaker OPEN after %d failures\n", cb.failures)
        }
        return err
    }

    if cb.state == "half-open" {
        cb.state = "closed"
        fmt.Println("🟢 Circuit breaker CLOSED")
    }
    cb.failures = 0
    return nil
}
```

**Verification**:
```bash
# Test Vision API directly
./scripts/test_vision_api.sh

# Monitor circuit breaker state
sudo docker logs -f liquorpro-sales-prod | grep "circuit breaker"
```

---

### Issue 8: Gemini API Timeouts

**Symptoms**:
- Brand normalization failing
- Logs show "Gemini API timeout"
- Slow response times

**Quick Check**:
```bash
# Check Gemini API performance
sudo docker logs liquorpro-sales-prod | grep "Gemini API took"

# Test API directly
curl -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent" \
  -H "Content-Type: application/json" \
  -d '{"contents":[{"parts":[{"text":"test"}]}]}'
```

**Common Causes**:
1. No timeout set on API calls
2. Gemini API experiencing high load
3. Request payload too large
4. Network latency

**Solutions**:

```go
// Solution 1: Add timeout to Gemini API calls
func callGeminiAPIWithTimeout(prompt string) (string, error) {
    ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
    defer cancel()

    resultChan := make(chan string, 1)
    errChan := make(chan error, 1)

    go func() {
        result, err := geminiClient.GenerateContent(ctx, prompt)
        if err != nil {
            errChan <- err
            return
        }
        resultChan <- result
    }()

    select {
    case result := <-resultChan:
        return result, nil
    case err := <-errChan:
        return "", err
    case <-ctx.Done():
        return "", fmt.Errorf("Gemini API timeout after 3s")
    }
}

// Solution 2: Add fallback when Gemini times out
func normalizeBrandNameWithFallback(rawName string) string {
    // Try Gemini first
    normalized, err := callGeminiAPIWithTimeout(rawName)
    if err == nil {
        return normalized
    }

    fmt.Printf("⚠️ Gemini API failed, using fallback: %v\n", err)

    // Fallback: basic text cleaning
    return basicBrandNormalization(rawName)
}

func basicBrandNormalization(rawName string) string {
    // Trim whitespace
    normalized := strings.TrimSpace(rawName)

    // Title case
    normalized = strings.Title(strings.ToLower(normalized))

    // Remove extra spaces
    normalized = regexp.MustCompile(`\s+`).ReplaceAllString(normalized, " ")

    return normalized
}

// Solution 3: Batch Gemini API calls
func normalizeBrandsBatch(brands []string) []string {
    // Combine into single prompt
    prompt := "Normalize these liquor brand names:\n\n"
    for i, brand := range brands {
        prompt += fmt.Sprintf("%d. %s\n", i+1, brand)
    }
    prompt += "\nReturn only the normalized names, one per line."

    response, err := callGeminiAPIWithTimeout(prompt)
    if err != nil {
        // Fallback to individual normalization
        return normalizeBrandsIndividually(brands)
    }

    return strings.Split(response, "\n")
}
```

**Verification**:
```bash
# Test with timeout
time curl -X POST "http://localhost:8092/api/ocr/normalize" \
  -d '{"brand": "grey goose"}'

# Should return in <5 seconds
```

---

## Data Quality Issues

### Issue 9: Low Overall Accuracy

**Symptoms**:
- OCR accuracy <90%
- Many fields incorrect or missing
- User complaints about data quality

**Quick Check**:
```bash
# Check current accuracy
./scripts/ocr_metrics_monitor.sh 10 | grep "accuracy"

# Check validation failures
sudo docker logs liquorpro-sales-prod | grep "validation failed" | wc -l
```

**Common Causes**:
1. Poor image quality
2. Insufficient fuzzy patterns
3. No cross-field validation
4. Missing fallback logic

**Solutions**:

```go
// Solution 1: Add image quality check
func checkImageQuality(imageData []byte) (string, error) {
    img, _, err := image.Decode(bytes.NewReader(imageData))
    if err != nil {
        return "error", err
    }

    bounds := img.Bounds()
    width := bounds.Dx()
    height := bounds.Dy()

    // Check resolution
    if width < 800 || height < 600 {
        return "low", fmt.Errorf("image resolution too low: %dx%d", width, height)
    }

    // Check if image is blurry (basic check)
    blurScore := calculateBlurScore(img)
    if blurScore < 100 {
        return "blurry", fmt.Errorf("image appears blurry (score: %.2f)", blurScore)
    }

    return "good", nil
}

// Solution 2: Add comprehensive validation
func validateExtraction(result *OCRResult) []ValidationError {
    errors := []ValidationError{}

    // Check required fields
    if result.Size == "" {
        errors = append(errors, ValidationError{Field: "Size", Message: "Missing size"})
    }
    if result.Price <= 0 {
        errors = append(errors, ValidationError{Field: "Price", Message: "Invalid price"})
    }

    // Cross-field validation
    if result.Size == "750ml" && result.Price > 0 && result.Price < 5 {
        errors = append(errors, ValidationError{
            Field:   "Price",
            Message: "750ml bottle price suspiciously low",
        })
    }

    if result.Category == "Wine" && result.Size == "50ml" {
        errors = append(errors, ValidationError{
            Field:   "Size",
            Message: "Wine rarely comes in 50ml (likely OCR error)",
        })
    }

    return errors
}

// Solution 3: Add confidence scoring
func calculateConfidenceScore(result *OCRResult) float64 {
    score := 1.0

    // Penalize missing fields
    if result.Size == "" {
        score -= 0.2
    }
    if result.BrandName == "" {
        score -= 0.3
    }
    if result.Price <= 0 {
        score -= 0.3
    }

    // Penalize suspicious patterns
    if strings.Contains(result.Size, "O") {  // Likely OCR error (0 vs O)
        score -= 0.1
    }

    // Bonus for cross-field consistency
    if validateCrossFields(result) {
        score += 0.1
    }

    return math.Max(0, score)
}

// Solution 4: Add human-in-the-loop for low confidence
func processOCRWithQualityGate(imageData []byte) (*OCRResult, error) {
    result := processOCR(imageData)
    confidence := calculateConfidenceScore(result)

    if confidence < 0.7 {
        // Flag for manual review
        flagForManualReview(result, confidence)
        return nil, fmt.Errorf("low confidence (%.2f), flagged for review", confidence)
    }

    return result, nil
}
```

**Verification**:
```bash
# Test with various image qualities
./scripts/test_image_quality.sh

# Monitor accuracy improvement
./scripts/ocr_metrics_monitor.sh 60
```

---

## Deployment Issues

### Issue 10: OCR Works Locally But Fails in Production

**Symptoms**:
- Tests pass locally
- Production deployment fails
- Different behavior in prod vs dev

**Quick Check**:
```bash
# Compare environments
echo "Local:"
go test -v ./internal/sales/services

echo "Production:"
sudo docker logs liquorpro-sales-prod --tail 50
```

**Common Causes**:
1. Environment variables missing in production
2. Different API credentials
3. Network connectivity differences
4. File path differences

**Solutions**:

```bash
# Solution 1: Verify environment variables
echo "Checking production environment..."
sudo docker exec liquorpro-sales-prod env | grep -E "(GEMINI|GOOGLE|VISION)"

# Solution 2: Test from within container
sudo docker exec -it liquorpro-sales-prod go test -v ./internal/sales/services

# Solution 3: Compare configurations
diff <(cat .env.development) <(sudo docker exec liquorpro-sales-prod cat /app/.env)

# Solution 4: Check network connectivity from container
sudo docker exec liquorpro-sales-prod curl -I https://vision.googleapis.com
sudo docker exec liquorpro-sales-prod curl -I https://generativelanguage.googleapis.com
```

**Code Solution**:
```go
// Add environment validation on startup
func validateEnvironment() error {
    required := []string{
        "GEMINI_API_KEY",
        "GOOGLE_APPLICATION_CREDENTIALS",
        "VISION_API_ENDPOINT",
    }

    missing := []string{}
    for _, key := range required {
        if os.Getenv(key) == "" {
            missing = append(missing, key)
        }
    }

    if len(missing) > 0 {
        return fmt.Errorf("missing required environment variables: %v", missing)
    }

    fmt.Println("✅ All required environment variables set")
    return nil
}
```

---

## Cache Issues

### Issue 11: Cache Not Working

**Symptoms**:
- Cache hit rate 0%
- Every request hits external APIs
- Slow performance

**Quick Check**:
```bash
# Check cache metrics
./scripts/ocr_metrics_monitor.sh 10 | grep "cache"

# Check Redis connectivity
docker exec liquorpro-redis-prod redis-cli ping
```

**Common Causes**:
1. Redis not connected
2. Cache key generation inconsistent
3. TTL too short
4. Cache disabled in config

**Solutions**:

```go
// Solution 1: Validate Redis connection on startup
func validateRedisConnection() error {
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()

    _, err := redisClient.Ping(ctx).Result()
    if err != nil {
        return fmt.Errorf("Redis connection failed: %w", err)
    }

    fmt.Println("✅ Redis connection validated")
    return nil
}

// Solution 2: Consistent cache key generation
func generateCacheKey(imageData []byte) string {
    // Use SHA256 hash for consistent keys
    hash := sha256.Sum256(imageData)
    return fmt.Sprintf("ocr:result:%s", hex.EncodeToString(hash[:]))
}

// Solution 3: Add cache warming
func warmCache() {
    fmt.Println("🔥 Warming cache with common requests...")

    commonSizes := []string{"750ml", "1175ml", "375ml", "500ml"}
    for _, size := range commonSizes {
        cacheKey := fmt.Sprintf("ocr:size:%s", size)
        redisClient.Set(context.Background(), cacheKey, size, 24*time.Hour)
    }

    fmt.Println("✅ Cache warmed")
}

// Solution 4: Add cache debugging
func getCachedValue(key string) (string, bool) {
    ctx := context.Background()

    val, err := redisClient.Get(ctx, key).Result()
    if err == redis.Nil {
        fmt.Printf("⚪ Cache miss: %s\n", key)
        return "", false
    } else if err != nil {
        fmt.Printf("🔴 Cache error: %v\n", err)
        return "", false
    }

    fmt.Printf("🟢 Cache hit: %s\n", key)
    return val, true
}
```

**Verification**:
```bash
# Monitor cache hits
watch -n 2 './scripts/ocr_metrics_monitor.sh 2 | grep cache'

# Check Redis keys
docker exec liquorpro-redis-prod redis-cli keys "ocr:*"
```

---

## Testing Issues

### Issue 12: Tests Failing Intermittently

**Symptoms**:
- Tests pass sometimes, fail other times
- Different results on different runs
- CI/CD pipeline unreliable

**Quick Check**:
```bash
# Run tests multiple times
for i in {1..10}; do
  echo "Run $i:"
  go test ./internal/sales/services
done
```

**Common Causes**:
1. Race conditions
2. Test data pollution
3. Non-deterministic behavior
4. External API dependencies

**Solutions**:

```go
// Solution 1: Add proper test cleanup
func TestOCRExtraction(t *testing.T) {
    // Setup
    cache := setupTestCache()

    // Cleanup after test
    t.Cleanup(func() {
        cleanupTestCache(cache)
    })

    // Test code
    result := extractOCR(testImage)
    assert.Equal(t, "750ml", result.Size)
}

// Solution 2: Use table-driven tests for determinism
func TestSizeDetection(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected string
    }{
        {"Standard", "750ml", "750ml"},
        {"OCR Error", "75Oml", "750ml"},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := detectSize(tt.input)
            if result != tt.expected {
                t.Errorf("Expected %s, got %s", tt.expected, result)
            }
        })
    }
}

// Solution 3: Mock external APIs
type MockVisionAPI struct {
    responses map[string]string
}

func (m *MockVisionAPI) DetectText(imageData []byte) (string, error) {
    hash := sha256.Sum256(imageData)
    key := hex.EncodeToString(hash[:])

    if response, ok := m.responses[key]; ok {
        return response, nil
    }

    return "", fmt.Errorf("no mock response for image")
}

// Solution 4: Use test helpers for isolation
func setupIsolatedTest(t *testing.T) (*TestEnvironment, func()) {
    env := &TestEnvironment{
        Cache:     NewTestCache(),
        VisionAPI: &MockVisionAPI{},
        DB:        setupTestDB(),
    }

    cleanup := func() {
        env.Cache.Clear()
        env.DB.Close()
    }

    return env, cleanup
}
```

---

## Emergency Procedures

### Procedure 1: Complete OCR Outage

**Symptoms**: 100% OCR requests failing

**Immediate Actions**:
```bash
# 1. Check service health (30 seconds)
curl https://api.liquorpro.com/health
./scripts/verify_deployment.sh

# 2. Check recent deployments (30 seconds)
git log --oneline -10
docker ps -a | grep sales

# 3. Check logs for errors (1 minute)
sudo docker logs liquorpro-sales-prod --tail 100 | grep -i error

# 4. If recent deployment, ROLLBACK (2 minutes)
./scripts/rollback.sh v1.0.50

# 5. If not deployment, check external APIs (1 minute)
curl -I https://vision.googleapis.com
curl -I https://generativelanguage.googleapis.com

# 6. Restart service (1 minute)
sudo -E bash -c "set -a; source .env.production; docker compose -f docker-compose.production.yml restart sales"

# 7. Verify recovery (1 minute)
./scripts/verify_deployment.sh
```

**Total Time**: <6 minutes to recovery

---

### Procedure 2: Degraded Performance

**Symptoms**: OCR working but slow

**Actions**:
```bash
# 1. Check resource usage
docker stats liquorpro-sales-prod --no-stream

# 2. Check for stuck processes
docker exec liquorpro-sales-prod ps aux

# 3. Check cache hit rate
./scripts/ocr_metrics_monitor.sh 5 | grep "cache"

# 4. Clear cache if hit rate is low
docker exec liquorpro-redis-prod redis-cli FLUSHDB

# 5. Warm cache
curl -X POST "http://localhost:8092/api/admin/warm-cache"

# 6. Monitor improvement
./scripts/ocr_metrics_monitor.sh 30
```

---

### Procedure 3: Data Quality Issues

**Symptoms**: OCR succeeding but extracting incorrect data

**Actions**:
```bash
# 1. Check current accuracy
./scripts/ocr_metrics_monitor.sh 10 | grep "accuracy"

# 2. Get sample of recent extractions
curl -H "Authorization: Bearer $TOKEN" \
  "https://api.liquorpro.com/api/ocr/recent?limit=10"

# 3. Check for pattern in failures
sudo docker logs liquorpro-sales-prod | grep "validation failed" | tail -20

# 4. If specific pattern, add quick fix
# (Edit code to add new fuzzy pattern)

# 5. Hot deploy fix
./scripts/hot_deploy.sh

# 6. Monitor accuracy improvement
./scripts/ocr_metrics_monitor.sh 60
```

---

## Quick Reference

### Decision Matrix

| Symptom | First Check | Most Likely Cause | Quick Fix |
|---------|-------------|-------------------|-----------|
| OCR not working at all | Health endpoint | API credentials or deployment issue | Restart service, check credentials |
| OCR slow | Processing time logs | No caching or large images | Enable caching, optimize images |
| Missing fields | Extraction rate | Missing patterns | Add fuzzy patterns |
| Wrong values | Validation failures | OCR errors not handled | Add OCR error correction |
| Intermittent failures | Run tests 10x | Race condition | Add mutex protection |
| High memory | Docker stats | Cache unbounded | Add LRU eviction |

### Command Cheat Sheet

```bash
# Health check
curl https://api.liquorpro.com/health

# Quick diagnostics
./scripts/verify_deployment.sh

# View logs
sudo docker logs liquorpro-sales-prod --tail 100 --follow

# Monitor metrics
./scripts/ocr_metrics_monitor.sh 60

# Run tests
go test ./internal/sales/services -v

# Restart service
sudo -E bash -c "docker compose -f docker-compose.production.yml restart sales"

# Rollback
./scripts/rollback.sh v1.0.50

# Clear cache
docker exec liquorpro-redis-prod redis-cli FLUSHDB
```

---

## Getting Help

If you can't resolve the issue using this guide:

1. **Check other guides**:
   - COMMON_PITFALLS.md for similar issues
   - REAL_WORLD_EXAMPLES.md for case studies
   - FAQ.md for common questions

2. **Gather diagnostic info**:
   ```bash
   ./scripts/generate_diagnostic_report.sh
   ```

3. **Create incident report** using template from TEMPLATES_PACKAGE.md

4. **Escalate** with:
   - Symptom description
   - Steps already tried
   - Diagnostic logs
   - Impact assessment

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0
**Maintained by**: OCR Development Team

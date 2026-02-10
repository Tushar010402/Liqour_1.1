# OCR Advanced Topics

**Purpose**: Advanced techniques and deep dives for experienced developers
**Prerequisites**: Complete all basic guides first
**Last Updated**: January 15, 2025

---

## 📑 Table of Contents

1. [Advanced Pattern Matching](#advanced-pattern-matching)
2. [Performance Optimization](#performance-optimization)
3. [Advanced Caching Strategies](#advanced-caching-strategies)
4. [Machine Learning Integration](#machine-learning-integration)
5. [Advanced Testing Techniques](#advanced-testing-techniques)
6. [Production Debugging](#production-debugging)
7. [Architecture & Scalability](#architecture--scalability)
8. [Security Hardening](#security-hardening)

---

## 1. Advanced Pattern Matching

### Weighted Fuzzy Matching

Beyond simple character substitution, use weighted scoring:

```go
type FuzzyMatcher struct {
    patterns map[string]float64  // pattern → weight
}

func (f *FuzzyMatcher) Match(text string) (string, float64) {
    bestMatch := ""
    bestScore := 0.0

    for pattern, weight := range f.patterns {
        if matched, _ := regexp.MatchString(pattern, text); matched {
            score := calculateMatchScore(text, pattern) * weight
            if score > bestScore {
                bestScore = score
                bestMatch = extractSize(pattern)
            }
        }
    }

    return bestMatch, bestScore
}

func calculateMatchScore(text, pattern string) float64 {
    // Factors to consider:
    // 1. How many characters match exactly
    // 2. Position of match (beginning is stronger)
    // 3. Context (surrounded by whitespace is stronger)

    score := 0.0

    // Position weight
    if strings.HasPrefix(text, extractPrefix(pattern)) {
        score += 0.3
    }

    // Context weight
    if hasWordBoundaries(text, pattern) {
        score += 0.3
    }

    // Exact match weight
    exactMatches := countExactMatches(text, pattern)
    score += float64(exactMatches) / float64(len(pattern)) * 0.4

    return score
}
```

### Context-Aware Pattern Matching

Use surrounding context to improve matches:

```go
func detectReceiptTypeWithContext(rawText string) string {
    lines := strings.Split(rawText, "\n")

    for i, line := range lines {
        // Get context (lines before and after)
        context := getContext(lines, i, 2)  // 2 lines each direction

        // Use context to validate match
        if size := fuzzyMatch(line); size != "" {
            if validateWithContext(size, context) {
                return size
            }
        }
    }

    return "unknown"
}

func validateWithContext(size string, context []string) bool {
    // Look for supporting evidence in context
    supportingKeywords := map[string][]string{
        "90ml":  {"nip", "small", "quarter"},
        "180ml": {"half pint", "small bottle"},
        "375ml": {"half", "pint", "medium"},
        "750ml": {"bottle", "full", "standard"},
    }

    for _, line := range context {
        for _, keyword := range supportingKeywords[size] {
            if strings.Contains(strings.ToLower(line), keyword) {
                return true
            }
        }
    }

    return false
}
```

### Probabilistic Pattern Matching

When multiple patterns could match, use probability:

```go
type PatternMatch struct {
    Pattern     string
    Probability float64
    Size        string
}

func probabilisticMatch(text string) PatternMatch {
    candidates := []PatternMatch{}

    // Collect all possible matches
    for _, pattern := range allPatterns {
        if matched, _ := regexp.MatchString(pattern.regex, text); matched {
            prob := calculateProbability(text, pattern)
            candidates = append(candidates, PatternMatch{
                Pattern:     pattern.name,
                Probability: prob,
                Size:        pattern.size,
            })
        }
    }

    // Return highest probability
    if len(candidates) == 0 {
        return PatternMatch{Probability: 0.0}
    }

    sort.Slice(candidates, func(i, j int) bool {
        return candidates[i].Probability > candidates[j].Probability
    })

    return candidates[0]
}

func calculateProbability(text string, pattern Pattern) float64 {
    prob := 0.5  // base probability

    // Adjust based on factors
    prob += pattern.historicalAccuracy * 0.3  // Historical success rate
    prob += contextStrength(text) * 0.2       // Context supporting evidence
    prob += patternSpecificity(pattern) * 0.1 // How specific the pattern is

    return math.Min(prob, 1.0)
}
```

---

## 2. Performance Optimization

### Benchmark-Driven Optimization

Always measure before optimizing:

```go
func BenchmarkFuzzyDetection(b *testing.B) {
    testCases := loadRealProductionData()  // Use real data!

    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        for _, tc := range testCases {
            _ = detectReceiptType(tc.text)
        }
    }
}

func BenchmarkCacheHitVsMiss(b *testing.B) {
    client := setupTestClient()

    b.Run("CacheHit", func(b *testing.B) {
        // Pre-populate cache
        client.cache["test"] = cacheEntry{value: "result", timestamp: time.Now()}

        b.ResetTimer()
        for i := 0; i < b.N; i++ {
            _, _ = client.NormalizeBrandNameWithCache(ctx, "test")
        }
    })

    b.Run("CacheMiss", func(b *testing.B) {
        b.ResetTimer()
        for i := 0; i < b.N; i++ {
            _, _ = client.NormalizeBrandNameWithCache(ctx, fmt.Sprintf("test%d", i))
        }
    })
}
```

### CPU Profiling

```go
import (
    "runtime/pprof"
    "os"
)

func profileCPU() {
    f, _ := os.Create("cpu.prof")
    defer f.Close()

    pprof.StartCPUProfile(f)
    defer pprof.StopCPUProfile()

    // Run your workload
    processLargeDataset()
}
```

Then analyze:
```bash
go tool pprof cpu.prof
# Commands in pprof:
# top10          - Show top 10 functions
# list funcName  - Show source of function
# web            - Generate call graph
```

### Memory Profiling

```go
func profileMemory() {
    f, _ := os.Create("mem.prof")
    defer f.Close()

    runtime.GC() // Get fresh memory state

    // Run your workload
    processLargeDataset()

    pprof.WriteHeapProfile(f)
}
```

### Optimization Patterns

**Pattern 1: String Builder for Concatenation**
```go
// ❌ BAD - Creates new string each iteration
func buildString(items []string) string {
    result := ""
    for _, item := range items {
        result += item + "\n"  // Slow!
    }
    return result
}

// ✅ GOOD - Efficient building
func buildString(items []string) string {
    var sb strings.Builder
    sb.Grow(len(items) * 50)  // Pre-allocate if you know approximate size

    for _, item := range items {
        sb.WriteString(item)
        sb.WriteString("\n")
    }
    return sb.String()
}
```

**Pattern 2: Regex Pooling**
```go
// For frequently used patterns
var regexPool = sync.Pool{
    New: func() interface{} {
        return regexp.MustCompile(`your-pattern`)
    },
}

func processWithPooledRegex(text string) bool {
    re := regexPool.Get().(*regexp.Regexp)
    defer regexPool.Put(re)

    return re.MatchString(text)
}
```

**Pattern 3: Batch Processing**
```go
// ❌ BAD - Process one at a time
func processItems(items []Item) []Result {
    results := []Result{}
    for _, item := range items {
        result := processItem(item)  // Individual API call
        results = append(results, result)
    }
    return results
}

// ✅ GOOD - Batch process
func processItemsBatch(items []Item) []Result {
    const batchSize = 50

    results := make([]Result, 0, len(items))

    for i := 0; i < len(items); i += batchSize {
        end := i + batchSize
        if end > len(items) {
            end = len(items)
        }

        batch := items[i:end]
        batchResults := processBatch(batch)  // Single API call
        results = append(results, batchResults...)
    }

    return results
}
```

---

## 3. Advanced Caching Strategies

### Multi-Level Cache

```go
type MultiLevelCache struct {
    l1 *sync.Map           // In-memory (fastest)
    l2 *redis.Client       // Redis (fast, shared)
    l3 *sql.DB             // Database (slow, persistent)
}

func (c *MultiLevelCache) Get(key string) (string, bool) {
    // Try L1 (memory)
    if val, ok := c.l1.Load(key); ok {
        metrics.CacheHit("L1")
        return val.(string), true
    }

    // Try L2 (Redis)
    if val, err := c.l2.Get(ctx, key).Result(); err == nil {
        metrics.CacheHit("L2")
        c.l1.Store(key, val)  // Promote to L1
        return val, true
    }

    // Try L3 (Database)
    if val, err := c.getFromDB(key); err == nil {
        metrics.CacheHit("L3")
        c.l2.Set(ctx, key, val, time.Hour)  // Promote to L2
        c.l1.Store(key, val)                // Promote to L1
        return val, true
    }

    metrics.CacheMiss()
    return "", false
}
```

### Cache Warming

```go
func warmCache(client *GeminiClient) {
    // Pre-populate cache with common brands
    commonBrands := getTopBrands(100)  // Top 100 brands by frequency

    fmt.Println("🔥 Warming cache...")

    var wg sync.WaitGroup
    semaphore := make(chan struct{}, 10)  // Limit concurrency

    for _, brand := range commonBrands {
        wg.Add(1)
        go func(b string) {
            defer wg.Done()

            semaphore <- struct{}{}        // Acquire
            defer func() { <-semaphore }() // Release

            if _, err := client.NormalizeBrandNameWithCache(ctx, b); err != nil {
                log.Printf("Failed to warm cache for %s: %v", b, err)
            }
        }(brand)
    }

    wg.Wait()
    fmt.Println("✅ Cache warmed")
}
```

### Cache Invalidation Strategies

```go
type CacheInvalidator struct {
    cache     *Cache
    listeners []chan string
}

// Pattern 1: Time-based invalidation (already implemented)
func (c *Cache) startTTLCleanup() {
    ticker := time.NewTicker(15 * time.Minute)
    go func() {
        for range ticker.C {
            c.cleanExpired()
        }
    }()
}

// Pattern 2: Event-based invalidation
func (ci *CacheInvalidator) InvalidatePattern(pattern string) {
    ci.cache.mutex.Lock()
    defer ci.cache.mutex.Unlock()

    for key := range ci.cache.data {
        if matched, _ := regexp.MatchString(pattern, key); matched {
            delete(ci.cache.data, key)
        }
    }

    // Notify listeners
    for _, listener := range ci.listeners {
        select {
        case listener <- pattern:
        default:
        }
    }
}

// Pattern 3: LRU eviction
type LRUCache struct {
    capacity int
    cache    map[string]*list.Element
    list     *list.List
    mutex    sync.RWMutex
}

func (c *LRUCache) Get(key string) (interface{}, bool) {
    c.mutex.Lock()
    defer c.mutex.Unlock()

    if elem, ok := c.cache[key]; ok {
        c.list.MoveToFront(elem)  // Mark as recently used
        return elem.Value.(cacheEntry).value, true
    }

    return nil, false
}

func (c *LRUCache) Put(key string, value interface{}) {
    c.mutex.Lock()
    defer c.mutex.Unlock()

    if elem, ok := c.cache[key]; ok {
        c.list.MoveToFront(elem)
        elem.Value = cacheEntry{key: key, value: value}
        return
    }

    // Add new entry
    entry := cacheEntry{key: key, value: value}
    elem := c.list.PushFront(entry)
    c.cache[key] = elem

    // Evict if over capacity
    if c.list.Len() > c.capacity {
        oldest := c.list.Back()
        if oldest != nil {
            c.list.Remove(oldest)
            delete(c.cache, oldest.Value.(cacheEntry).key)
        }
    }
}
```

---

## 4. Machine Learning Integration

### Building Training Data from OCR Results

```go
func collectTrainingData() {
    // Collect successful OCR results
    results := querySuccessfulOCRResults(last30Days)

    trainingData := make([]TrainingExample, 0, len(results))

    for _, result := range results {
        example := TrainingExample{
            Input:  result.RawOCRText,
            Output: result.ExtractedData,
            Metadata: map[string]interface{}{
                "confidence": result.Confidence,
                "manual_corrections": result.ManualCorrections,
                "receipt_type": result.Type,
            },
        }
        trainingData = append(trainingData, example)
    }

    // Export for ML training
    exportToJSON(trainingData, "training_data.json")
}
```

### Confidence Scoring

```go
type ExtractionResult struct {
    Brand      string
    Size       string
    Price      float64
    Confidence ConfidenceScore
}

type ConfidenceScore struct {
    Overall    float64  // 0.0 - 1.0
    Brand      float64
    Size       float64
    Price      float64
    Factors    map[string]float64
}

func calculateConfidence(result *ocr.ExtractedBrand, rawText string) ConfidenceScore {
    score := ConfidenceScore{
        Factors: make(map[string]float64),
    }

    // Factor 1: Pattern match strength
    score.Factors["pattern_match"] = calculatePatternStrength(rawText)

    // Factor 2: Validation pass rate
    score.Factors["validation"] = calculateValidationScore(result)

    // Factor 3: Historical accuracy for this brand
    score.Factors["historical"] = getHistoricalAccuracy(result.Brand)

    // Factor 4: OCR quality
    score.Factors["ocr_quality"] = estimateOCRQuality(rawText)

    // Calculate component scores
    score.Brand = calculateBrandConfidence(result, rawText)
    score.Size = calculateSizeConfidence(result, rawText)
    score.Price = calculatePriceConfidence(result, rawText)

    // Overall score (weighted average)
    score.Overall = (score.Brand * 0.4) + (score.Size * 0.3) + (score.Price * 0.3)

    return score
}
```

### A/B Testing New Algorithms

```go
type ExperimentConfig struct {
    Name            string
    Percentage      int     // % of traffic to use new algorithm
    NewAlgorithm    func(string) Result
    LegacyAlgorithm func(string) Result
}

func runExperiment(config ExperimentConfig, input string) Result {
    // Assign to experiment group based on hash
    hash := hashString(input)
    useNew := (hash % 100) < config.Percentage

    var result Result
    var algorithmUsed string

    if useNew {
        result = config.NewAlgorithm(input)
        algorithmUsed = "new"
    } else {
        result = config.LegacyAlgorithm(input)
        algorithmUsed = "legacy"
    }

    // Log for analysis
    metrics.RecordExperiment(metrics.ExperimentData{
        Experiment: config.Name,
        Algorithm:  algorithmUsed,
        Input:      input,
        Result:     result,
        Timestamp:  time.Now(),
    })

    return result
}
```

---

## 5. Advanced Testing Techniques

### Property-Based Testing

```go
import "testing/quick"

func TestFuzzyDetection_Properties(t *testing.T) {
    // Property: Any valid size pattern should be detected
    property := func(size int) bool {
        validSizes := map[int]string{
            90:  "90ml",
            180: "180ml",
            375: "375ml",
            750: "750ml",
        }

        expected, exists := validSizes[size]
        if !exists {
            return true  // Skip invalid sizes
        }

        // Generate various representations
        inputs := []string{
            fmt.Sprintf("%dml", size),
            fmt.Sprintf("%d ml", size),
            fmt.Sprintf("%d M.L", size),
        }

        for _, input := range inputs {
            result := detectReceiptType(input)
            if result != expected {
                t.Logf("Failed for input %q: got %q, want %q", input, result, expected)
                return false
            }
        }

        return true
    }

    if err := quick.Check(property, nil); err != nil {
        t.Error(err)
    }
}
```

### Fuzzing

```go
func FuzzReceiptTypeDetection(f *testing.F) {
    // Seed corpus with known good inputs
    f.Add("90ml")
    f.Add("180 M.L")
    f.Add("750 ml")

    f.Fuzz(func(t *testing.T, input string) {
        // Should not panic
        result := detectReceiptType(input)

        // If it returns a size, verify it's valid
        validSizes := []string{"90ml", "180ml", "375ml", "750ml", "unknown"}
        valid := false
        for _, size := range validSizes {
            if result == size {
                valid = true
                break
            }
        }

        if !valid {
            t.Errorf("Invalid size returned: %q", result)
        }
    })
}
```

### Mutation Testing

```bash
# Install mutation testing tool
go install github.com/zimmski/go-mutesting/cmd/go-mutesting@latest

# Run mutation testing
go-mutesting ./internal/sales/services/ocr_service.go

# Check mutation score (should be >80%)
```

### Chaos Engineering for Tests

```go
type ChaosConfig struct {
    FailureRate     float64  // 0.0 - 1.0
    LatencyMs       int
    ReturnNil       bool
    CorruptData     bool
}

func TestWithChaos(t *testing.T) {
    chaos := ChaosConfig{
        FailureRate: 0.1,   // 10% failure rate
        LatencyMs:   100,    // Add 100ms latency
    }

    client := &ChaoticGeminiClient{
        realClient: setupRealClient(),
        chaos:      chaos,
    }

    // Run tests - should handle chaos gracefully
    for i := 0; i < 100; i++ {
        result, err := client.NormalizeBrandName(ctx, "Test Brand")

        // System should handle failures
        if err != nil {
            t.Logf("Expected chaos failure: %v", err)
            continue
        }

        // Verify result when successful
        if result == "" {
            t.Error("Empty result without error")
        }
    }
}
```

---

## 6. Production Debugging

### Distributed Tracing

```go
import "go.opentelemetry.io/otel"

func processWithTracing(ctx context.Context, brand string) (string, error) {
    ctx, span := otel.Tracer("ocr-service").Start(ctx, "ProcessBrand")
    defer span.End()

    span.SetAttributes(
        attribute.String("brand.original", brand),
    )

    // Step 1: Normalize
    ctx, span1 := otel.Tracer("ocr-service").Start(ctx, "NormalizeBrand")
    normalized, err := normalizeBrand(ctx, brand)
    span1.End()

    if err != nil {
        span.RecordError(err)
        return "", err
    }

    span.SetAttributes(
        attribute.String("brand.normalized", normalized),
    )

    // Step 2: Validate
    ctx, span2 := otel.Tracer("ocr-service").Start(ctx, "ValidateBrand")
    if err := validate(ctx, normalized); err != nil {
        span2.RecordError(err)
        span2.End()
        return "", err
    }
    span2.End()

    return normalized, nil
}
```

### Dynamic Logging Levels

```go
var logLevel = atomic.Value{}

func init() {
    logLevel.Store("INFO")  // Default level
}

func setLogLevel(level string) {
    logLevel.Store(level)
}

func debugLog(format string, args ...interface{}) {
    if logLevel.Load().(string) == "DEBUG" {
        log.Printf("[DEBUG] "+format, args...)
    }
}

// Enable via HTTP endpoint or signal
http.HandleFunc("/debug/loglevel", func(w http.ResponseWriter, r *http.Request) {
    level := r.URL.Query().Get("level")
    setLogLevel(level)
    fmt.Fprintf(w, "Log level set to: %s\n", level)
})
```

### Live Debug Sessions

```go
// Add debug endpoint (only in dev/staging!)
if os.Getenv("ENABLE_DEBUG") == "true" {
    http.HandleFunc("/debug/brand", func(w http.ResponseWriter, r *http.Request) {
        brand := r.URL.Query().Get("brand")

        // Enable verbose logging for this request
        ctx := context.WithValue(r.Context(), "debug", true)

        result, err := processBrandWithFullLogging(ctx, brand)

        response := map[string]interface{}{
            "input":  brand,
            "result": result,
            "error":  err,
            "logs":   getDebugLogs(ctx),
        }

        json.NewEncoder(w).Encode(response)
    })
}
```

---

## 7. Architecture & Scalability

### Horizontal Scaling

```go
// Design for stateless processing
type OCRProcessor struct {
    // No instance state - uses only parameters
}

func (p *OCRProcessor) Process(ctx context.Context, image []byte) (*Result, error) {
    // All state passed in or retrieved from shared store
    // Can run on any instance
}
```

### Event-Driven Architecture

```go
type EventBus struct {
    subscribers map[string][]chan Event
}

func (eb *EventBus) Publish(event Event) {
    for _, subscriber := range eb.subscribers[event.Type] {
        select {
        case subscriber <- event:
        default:
            // Non-blocking
        }
    }
}

// Example: Cache invalidation events
func setupCacheInvalidation(bus *EventBus, cache *Cache) {
    ch := make(chan Event, 100)
    bus.Subscribe("brand.updated", ch)

    go func() {
        for event := range ch {
            brandName := event.Data["brand"].(string)
            cache.Invalidate(brandName)
            log.Printf("Cache invalidated for brand: %s", brandName)
        }
    }()
}
```

### Circuit Breaker Pattern

```go
type CircuitBreaker struct {
    maxFailures  int
    resetTimeout time.Duration
    failures     int
    lastFailure  time.Time
    state        State
    mutex        sync.RWMutex
}

type State int

const (
    StateClosed State = iota  // Normal operation
    StateOpen                  // Failing, reject requests
    StateHalfOpen             // Testing if recovered
)

func (cb *CircuitBreaker) Call(fn func() error) error {
    cb.mutex.RLock()
    state := cb.state
    cb.mutex.RUnlock()

    switch state {
    case StateOpen:
        // Check if should try again
        if time.Since(cb.lastFailure) > cb.resetTimeout {
            cb.setState(StateHalfOpen)
        } else {
            return errors.New("circuit breaker open")
        }

    case StateHalfOpen:
        // Allow one request to test
    }

    // Execute function
    err := fn()

    cb.mutex.Lock()
    defer cb.mutex.Unlock()

    if err != nil {
        cb.failures++
        cb.lastFailure = time.Now()

        if cb.failures >= cb.maxFailures {
            cb.state = StateOpen
        }

        return err
    }

    // Success - reset
    cb.failures = 0
    cb.state = StateClosed

    return nil
}
```

---

## 8. Security Hardening

### Input Sanitization

```go
func sanitizeInput(input string) string {
    // Remove control characters
    input = removeControlChars(input)

    // Limit length
    maxLen := 10000
    if len(input) > maxLen {
        input = input[:maxLen]
    }

    // Remove potentially malicious patterns
    dangerousPatterns := []string{
        `<script`,
        `javascript:`,
        `onload=`,
        `onerror=`,
    }

    for _, pattern := range dangerousPatterns {
        input = strings.ReplaceAll(input, pattern, "")
    }

    return input
}
```

### Rate Limiting

```go
type RateLimiter struct {
    requests map[string]*TokenBucket
    mutex    sync.RWMutex
}

type TokenBucket struct {
    tokens    float64
    capacity  float64
    refillRate float64  // tokens per second
    lastRefill time.Time
}

func (rl *RateLimiter) Allow(key string) bool {
    rl.mutex.Lock()
    defer rl.mutex.Unlock()

    bucket, exists := rl.requests[key]
    if !exists {
        bucket = &TokenBucket{
            tokens:     10,
            capacity:   10,
            refillRate: 1,  // 1 token per second
            lastRefill: time.Now(),
        }
        rl.requests[key] = bucket
    }

    // Refill tokens
    now := time.Now()
    elapsed := now.Sub(bucket.lastRefill).Seconds()
    bucket.tokens = math.Min(bucket.capacity, bucket.tokens + elapsed*bucket.refillRate)
    bucket.lastRefill = now

    // Check if request allowed
    if bucket.tokens >= 1 {
        bucket.tokens--
        return true
    }

    return false
}
```

### API Key Rotation

```go
type APIKeyManager struct {
    keys     []string
    current  int
    mutex    sync.RWMutex
    rotation time.Duration
}

func (m *APIKeyManager) GetKey() string {
    m.mutex.RLock()
    defer m.mutex.RUnlock()

    return m.keys[m.current]
}

func (m *APIKeyManager) startRotation() {
    ticker := time.NewTicker(m.rotation)
    go func() {
        for range ticker.C {
            m.mutex.Lock()
            m.current = (m.current + 1) % len(m.keys)
            m.mutex.Unlock()

            log.Printf("Rotated to API key #%d", m.current)
        }
    }()
}
```

---

## 🎓 Further Learning

### Books
- "Site Reliability Engineering" by Google
- "Designing Data-Intensive Applications" by Martin Kleppmann
- "Release It!" by Michael Nygard

### Tools to Explore
- OpenTelemetry for distributed tracing
- Prometheus for metrics
- Grafana for visualization
- k6 for load testing
- Chaos Mesh for chaos engineering

### Advanced Go Topics
- Generics (Go 1.18+)
- Context propagation
- Worker pools
- Memory management
- Garbage collector tuning

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0

---

> **Remember**: Advanced techniques should be used judiciously. Always start simple and add complexity only when needed!

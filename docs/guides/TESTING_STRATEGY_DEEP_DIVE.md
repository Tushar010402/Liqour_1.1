# Testing Strategy Deep Dive

**Comprehensive Guide to Testing OCR Systems**

**Reading Time**: 25 minutes
**Last Updated**: January 15, 2025
**Difficulty**: Intermediate to Advanced

---

## Table of Contents

1. [Testing Philosophy](#testing-philosophy)
2. [Testing Pyramid for OCR](#testing-pyramid-for-ocr)
3. [Unit Testing](#unit-testing)
4. [Integration Testing](#integration-testing)
5. [End-to-End Testing](#end-to-end-testing)
6. [Property-Based Testing](#property-based-testing)
7. [Fuzzing](#fuzzing)
8. [Performance Testing](#performance-testing)
9. [Visual Regression Testing](#visual-regression-testing)
10. [Testing External APIs](#testing-external-apis)
11. [Test Data Management](#test-data-management)
12. [CI/CD Integration](#cicd-integration)
13. [Test Metrics](#test-metrics)

---

## Testing Philosophy

### Core Principles

**1. Test Behavior, Not Implementation**
```go
// ❌ BAD - Testing implementation details
func TestDetectSize_UsesRegex(t *testing.T) {
    // Don't test that it uses regex internally
    assert.Contains(t, detectSizeCode, "regexp.MustCompile")
}

// ✅ GOOD - Testing behavior
func TestDetectSize_HandlesOCRErrors(t *testing.T) {
    // Test that OCR errors are correctly handled
    result := detectSize("75Oml")  // O instead of 0
    assert.Equal(t, "750ml", result)
}
```

**2. Write Tests First (TDD)**
```go
// Step 1: Write failing test
func TestDetect1175ml(t *testing.T) {
    result := detectSize("1175ml")
    assert.Equal(t, "1175ml", result)  // Currently fails
}

// Step 2: Implement minimal code to pass
func detectSize(text string) string {
    if strings.Contains(text, "1175") {
        return "1175ml"
    }
    return "unknown"
}

// Step 3: Refactor while keeping test green
```

**3. One Assert Per Test (When Possible)**
```go
// ❌ BAD - Multiple unrelated assertions
func TestOCRExtraction(t *testing.T) {
    result := extractOCR(testImage)
    assert.Equal(t, "750ml", result.Size)
    assert.Equal(t, "Grey Goose", result.Brand)
    assert.Equal(t, 29.99, result.Price)
}

// ✅ GOOD - Separate focused tests
func TestOCRExtraction_Size(t *testing.T) {
    result := extractOCR(testImage)
    assert.Equal(t, "750ml", result.Size)
}

func TestOCRExtraction_Brand(t *testing.T) {
    result := extractOCR(testImage)
    assert.Equal(t, "Grey Goose", result.Brand)
}

func TestOCRExtraction_Price(t *testing.T) {
    result := extractOCR(testImage)
    assert.Equal(t, 29.99, result.Price)
}
```

**4. Tests Should Be FIRST**
- **Fast**: Run in milliseconds
- **Independent**: No dependencies between tests
- **Repeatable**: Same result every time
- **Self-Validating**: Clear pass/fail
- **Timely**: Written before or with code

---

## Testing Pyramid for OCR

```
        E2E Tests (10%)
       Full system with real images
      /                            \
     /     Integration Tests (30%)  \
    /      Service + API + Cache     \
   /                                  \
  /        Unit Tests (60%)            \
 /     Individual functions & logic     \
/________________________________________\
```

### Distribution Guidelines

| Test Type | % of Tests | Execution Time | Scope |
|-----------|-----------|----------------|-------|
| Unit | 60% | <1s total | Single function |
| Integration | 30% | <10s total | Multiple components |
| E2E | 10% | <60s total | Full system |

---

## Unit Testing

### Pattern 1: Table-Driven Tests

**Best for**: Testing multiple inputs with same logic

```go
func TestDetectReceiptType(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected string
    }{
        // Standard sizes
        {"Standard 750ml", "Product 750ml", "750ml"},
        {"Standard 1175ml", "Product 1175ml", "1175ml"},
        {"Standard 375ml", "Product 375ml", "375ml"},

        // OCR errors: 0 ↔ O
        {"OCR 0→O in 750ml", "Product 75Oml", "750ml"},
        {"OCR O→0 in 500ml", "Product 5O0ml", "500ml"},

        // OCR errors: 1 ↔ l ↔ I
        {"OCR 1→l in 1175ml", "Product 1l75ml", "1175ml"},
        {"OCR 1→I in 1175ml", "Product 1I75ml", "1175ml"},

        // OCR errors: 5 ↔ S
        {"OCR 5→S in 750ml", "Product 7S0ml", "750ml"},
        {"OCR S→5 in 500ml", "Product 50Oml", "500ml"},

        // Edge cases
        {"Extra whitespace", "Product  750  ml", "750ml"},
        {"No space", "Product750ml", "750ml"},
        {"Case insensitive", "Product 750ML", "750ml"},
        {"With period", "Product 750.ml", "750ml"},

        // Unknown/Invalid
        {"Unknown size", "Product XYZ", "unknown"},
        {"Empty string", "", "unknown"},
        {"Only numbers", "123", "unknown"},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := detectReceiptType(tt.input)
            if result != tt.expected {
                t.Errorf("detectReceiptType(%q) = %q, want %q",
                    tt.input, result, tt.expected)
            }
        })
    }
}
```

### Pattern 2: Subtests with Setup/Teardown

```go
func TestCacheOperations(t *testing.T) {
    // Shared setup
    cache := NewCache()

    t.Run("Get non-existent key", func(t *testing.T) {
        val, exists := cache.Get("nonexistent")
        assert.False(t, exists)
        assert.Empty(t, val)
    })

    t.Run("Set and Get", func(t *testing.T) {
        cache.Set("key1", "value1")
        val, exists := cache.Get("key1")
        assert.True(t, exists)
        assert.Equal(t, "value1", val)
    })

    t.Run("Expiration", func(t *testing.T) {
        cache.SetWithTTL("key2", "value2", 1*time.Millisecond)
        time.Sleep(10 * time.Millisecond)
        _, exists := cache.Get("key2")
        assert.False(t, exists)
    })

    // Shared teardown
    t.Cleanup(func() {
        cache.Clear()
    })
}
```

### Pattern 3: Test Helpers

```go
// Test helper for creating test images
func createTestImage(text string) []byte {
    img := image.NewRGBA(image.Rect(0, 0, 100, 100))
    // Draw text on image
    drawText(img, text, 10, 10)

    var buf bytes.Buffer
    png.Encode(&buf, img)
    return buf.Bytes()
}

// Test helper for creating OCR result
func createTestOCRResult(size, brand string, price float64) *OCRResult {
    return &OCRResult{
        Size:      size,
        BrandName: brand,
        Price:     price,
        Timestamp: time.Now(),
    }
}

// Usage in tests
func TestExtractBrand(t *testing.T) {
    imageData := createTestImage("Grey Goose 750ml $29.99")
    result := extractOCR(imageData)
    assert.Equal(t, "Grey Goose", result.BrandName)
}
```

### Pattern 4: Testing Error Paths

```go
func TestParsePrice_Errors(t *testing.T) {
    tests := []struct {
        name        string
        input       string
        expectError bool
        errorMsg    string
    }{
        {"Empty string", "", true, "empty price"},
        {"Invalid format", "abc", true, "invalid format"},
        {"Negative price", "-10.00", true, "negative price"},
        {"Too high", "999999.00", true, "exceeds maximum"},
        {"Valid price", "29.99", false, ""},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            _, err := parsePrice(tt.input)

            if tt.expectError {
                assert.Error(t, err)
                assert.Contains(t, err.Error(), tt.errorMsg)
            } else {
                assert.NoError(t, err)
            }
        })
    }
}
```

### Pattern 5: Mocking Dependencies

```go
// Interface for external dependency
type VisionAPI interface {
    DetectText(imageData []byte) (string, error)
}

// Mock implementation
type MockVisionAPI struct {
    DetectTextFunc func([]byte) (string, error)
    CallCount      int
}

func (m *MockVisionAPI) DetectText(imageData []byte) (string, error) {
    m.CallCount++
    if m.DetectTextFunc != nil {
        return m.DetectTextFunc(imageData)
    }
    return "Mock text", nil
}

// Test using mock
func TestOCRExtraction_WithMock(t *testing.T) {
    mockAPI := &MockVisionAPI{
        DetectTextFunc: func(data []byte) (string, error) {
            return "Grey Goose 750ml $29.99", nil
        },
    }

    extractor := NewOCRExtractor(mockAPI)
    result := extractor.Extract(testImageData)

    assert.Equal(t, "750ml", result.Size)
    assert.Equal(t, 1, mockAPI.CallCount)
}
```

---

## Integration Testing

### Pattern 1: Testing with Real Dependencies

```go
func TestOCRService_Integration(t *testing.T) {
    if testing.Short() {
        t.Skip("Skipping integration test in short mode")
    }

    // Setup real dependencies
    cache := setupTestRedis(t)
    db := setupTestDB(t)
    visionAPI := setupTestVisionAPI(t)

    // Cleanup
    t.Cleanup(func() {
        cache.FlushDB()
        db.Close()
    })

    // Create service with real dependencies
    service := NewOCRService(cache, db, visionAPI)

    // Test end-to-end flow
    result, err := service.ProcessInvoice(testImageData)

    assert.NoError(t, err)
    assert.NotNil(t, result)
    assert.Equal(t, "750ml", result.Size)

    // Verify cache was populated
    cached, exists := cache.Get("ocr:" + imageHash)
    assert.True(t, exists)
}
```

### Pattern 2: Testing Cache Behavior

```go
func TestCacheIntegration(t *testing.T) {
    cache := setupTestRedis(t)
    t.Cleanup(func() { cache.FlushDB() })

    service := NewOCRService(cache, nil, nil)

    // First call - cache miss
    start := time.Now()
    result1 := service.ProcessInvoice(testImageData)
    firstCallTime := time.Since(start)

    // Second call - cache hit (should be faster)
    start = time.Now()
    result2 := service.ProcessInvoice(testImageData)
    secondCallTime := time.Since(start)

    assert.Equal(t, result1, result2)
    assert.Less(t, secondCallTime, firstCallTime)

    // Verify cache metrics
    metrics := service.GetCacheMetrics()
    assert.Equal(t, 1, metrics.Hits)
    assert.Equal(t, 1, metrics.Misses)
}
```

### Pattern 3: Testing Database Integration

```go
func TestDatabaseIntegration(t *testing.T) {
    db := setupTestDB(t)
    t.Cleanup(func() { cleanupTestDB(db) })

    repo := NewOCRRepository(db)

    // Test insert
    result := &OCRResult{
        ID:        uuid.New(),
        Size:      "750ml",
        BrandName: "Grey Goose",
        Price:     29.99,
    }

    err := repo.Save(result)
    assert.NoError(t, err)

    // Test retrieve
    retrieved, err := repo.GetByID(result.ID)
    assert.NoError(t, err)
    assert.Equal(t, result.Size, retrieved.Size)
    assert.Equal(t, result.BrandName, retrieved.BrandName)

    // Test update
    retrieved.Price = 31.99
    err = repo.Update(retrieved)
    assert.NoError(t, err)

    updated, _ := repo.GetByID(result.ID)
    assert.Equal(t, 31.99, updated.Price)
}
```

### Pattern 4: Testing API Endpoints

```go
func TestOCREndpoint_Integration(t *testing.T) {
    // Setup test server
    router := setupTestRouter()
    server := httptest.NewServer(router)
    defer server.Close()

    // Prepare request
    imageData := loadTestImage("test_invoice.jpg")
    body := &bytes.Buffer{}
    writer := multipart.NewWriter(body)
    part, _ := writer.CreateFormFile("image", "test.jpg")
    part.Write(imageData)
    writer.Close()

    // Send request
    req, _ := http.NewRequest("POST", server.URL+"/api/ocr/extract", body)
    req.Header.Set("Content-Type", writer.FormDataContentType())
    req.Header.Set("Authorization", "Bearer "+testToken)

    resp, err := http.DefaultClient.Do(req)
    assert.NoError(t, err)
    assert.Equal(t, http.StatusOK, resp.StatusCode)

    // Parse response
    var result OCRResult
    json.NewDecoder(resp.Body).Decode(&result)
    assert.Equal(t, "750ml", result.Size)
}
```

---

## End-to-End Testing

### Pattern 1: Full System Test

```go
func TestE2E_InvoiceProcessing(t *testing.T) {
    if os.Getenv("E2E_TESTS") != "true" {
        t.Skip("Skipping E2E test (set E2E_TESTS=true to run)")
    }

    // Use production-like environment
    apiURL := os.Getenv("TEST_API_URL")
    token := getTestAuthToken()

    // Upload invoice
    invoiceID := uploadInvoice(t, apiURL, token, "test_invoice.jpg")

    // Wait for processing
    time.Sleep(2 * time.Second)

    // Retrieve result
    result := getOCRResult(t, apiURL, token, invoiceID)

    // Verify complete extraction
    assert.Equal(t, "750ml", result.Size)
    assert.Equal(t, "Grey Goose", result.BrandName)
    assert.Equal(t, 29.99, result.Price)
    assert.Equal(t, "Vodka", result.Category)

    // Verify stored in database
    dbResult := queryDatabase(t, invoiceID)
    assert.Equal(t, result, dbResult)

    // Verify cached
    cacheResult := queryCa che(t, invoiceID)
    assert.Equal(t, result, cacheResult)
}
```

### Pattern 2: Batch Processing Test

```go
func TestE2E_BatchProcessing(t *testing.T) {
    if testing.Short() {
        t.Skip("Skipping E2E batch test")
    }

    // Upload batch of 10 invoices
    invoiceIDs := uploadBatch(t, 10)

    // Wait for all to complete
    waitForBatchComplete(t, invoiceIDs, 30*time.Second)

    // Verify all processed successfully
    results := getBatchResults(t, invoiceIDs)
    assert.Equal(t, 10, len(results))

    successCount := 0
    for _, result := range results {
        if result.Status == "success" {
            successCount++
        }
    }

    // Accept 95% success rate (some images may be poor quality)
    assert.GreaterOrEqual(t, successCount, 9)
}
```

---

## Property-Based Testing

**Property-based testing** verifies that certain properties hold for all inputs.

### Example 1: Size Detection Properties

```go
import "testing/quick"

func TestSizeDetection_Properties(t *testing.T) {
    // Property 1: Detection should be idempotent
    f1 := func(text string) bool {
        result1 := detectSize(text)
        result2 := detectSize(result1)
        return result1 == result2
    }
    if err := quick.Check(f1, nil); err != nil {
        t.Errorf("Idempotence property failed: %v", err)
    }

    // Property 2: Should be case-insensitive
    f2 := func(text string) bool {
        lower := detectSize(strings.ToLower(text))
        upper := detectSize(strings.ToUpper(text))
        return lower == upper
    }
    if err := quick.Check(f2, nil); err != nil {
        t.Errorf("Case insensitivity failed: %v", err)
    }

    // Property 3: Adding whitespace shouldn't change result
    f3 := func(text string) bool {
        original := detectSize(text)
        withSpaces := detectSize(" " + text + " ")
        return original == withSpaces
    }
    if err := quick.Check(f3, nil); err != nil {
        t.Errorf("Whitespace invariance failed: %v", err)
    }
}
```

### Example 2: Price Parsing Properties

```go
func TestPriceParser_Properties(t *testing.T) {
    // Property: Parsing and formatting should be inverse operations
    f := func(price float64) bool {
        if price < 0 || price > 1000 {
            return true  // Skip invalid prices
        }

        formatted := fmt.Sprintf("$%.2f", price)
        parsed, err := parsePrice(formatted)

        if err != nil {
            return false
        }

        // Allow small floating point errors
        diff := math.Abs(price - parsed)
        return diff < 0.01
    }

    config := &quick.Config{MaxCount: 1000}
    if err := quick.Check(f, config); err != nil {
        t.Errorf("Parse/format inverse property failed: %v", err)
    }
}
```

---

## Fuzzing

**Fuzzing** automatically generates random inputs to find edge cases.

### Example 1: Fuzz Size Detection

```go
func FuzzDetectSize(f *testing.F) {
    // Seed corpus with known inputs
    f.Add("750ml")
    f.Add("1175ml")
    f.Add("75Oml")  // OCR error
    f.Add("")
    f.Add("invalid")

    f.Fuzz(func(t *testing.T, input string) {
        // Function should never panic
        defer func() {
            if r := recover(); r != nil {
                t.Errorf("detectSize panicked on input %q: %v", input, r)
            }
        }()

        result := detectSize(input)

        // Result should always be a valid size or "unknown"
        validSizes := []string{"750ml", "1175ml", "375ml", "500ml", "unknown"}
        isValid := false
        for _, valid := range validSizes {
            if result == valid {
                isValid = true
                break
            }
        }

        if !isValid {
            t.Errorf("detectSize(%q) returned invalid size: %q", input, result)
        }
    })
}

// Run: go test -fuzz=FuzzDetectSize -fuzztime=30s
```

### Example 2: Fuzz Price Parser

```go
func FuzzParsePrice(f *testing.F) {
    // Seed corpus
    f.Add("$29.99")
    f.Add("$1,234.56")
    f.Add("invalid")
    f.Add("$-100")

    f.Fuzz(func(t *testing.T, input string) {
        price, err := parsePrice(input)

        // If no error, price must be valid
        if err == nil {
            if price < 0 {
                t.Errorf("parsePrice(%q) returned negative price: %.2f", input, price)
            }
            if price > 10000 {
                t.Errorf("parsePrice(%q) returned unrealistic price: %.2f", input, price)
            }
        }

        // Function should never panic
        defer func() {
            if r := recover(); r != nil {
                t.Errorf("parsePrice panicked on input %q: %v", input, r)
            }
        }()
    })
}
```

---

## Performance Testing

### Benchmark Tests

```go
func BenchmarkDetectSize(b *testing.B) {
    inputs := []string{"750ml", "1175ml", "75Oml", "Product 750ml"}

    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        for _, input := range inputs {
            _ = detectSize(input)
        }
    }
}

func BenchmarkOCRExtraction(b *testing.B) {
    imageData := loadTestImage("test_invoice.jpg")

    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        _ = extractOCR(imageData)
    }
}

func BenchmarkCacheLookup(b *testing.B) {
    cache := NewCache()
    cache.Set("key1", "value1")

    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        _, _ = cache.Get("key1")
    }
}

// Run: go test -bench=. -benchmem
```

### Load Testing

```go
func TestOCRService_LoadTest(t *testing.T) {
    if testing.Short() {
        t.Skip("Skipping load test")
    }

    service := setupTestService(t)
    imageData := loadTestImage("test_invoice.jpg")

    // Simulate 100 concurrent requests
    concurrency := 100
    iterations := 10

    var wg sync.WaitGroup
    start := time.Now()

    for i := 0; i < concurrency; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            for j := 0; j < iterations; j++ {
                _, err := service.ProcessInvoice(imageData)
                assert.NoError(t, err)
            }
        }()
    }

    wg.Wait()
    duration := time.Since(start)

    totalRequests := concurrency * iterations
    rps := float64(totalRequests) / duration.Seconds()

    t.Logf("Processed %d requests in %v (%.2f req/s)", totalRequests, duration, rps)

    // Assert minimum performance
    assert.Greater(t, rps, 50.0, "Should handle at least 50 requests/second")
}
```

---

## Visual Regression Testing

### Testing OCR Output Consistency

```go
func TestOCRConsistency(t *testing.T) {
    // Load baseline results
    baseline := loadBaselineResults("testdata/baseline.json")

    // Process same images
    testImages := []string{"invoice1.jpg", "invoice2.jpg", "invoice3.jpg"}

    for _, imageName := range testImages {
        imageData := loadTestImage(imageName)
        result := extractOCR(imageData)

        expected := baseline[imageName]

        // Verify results match baseline
        assert.Equal(t, expected.Size, result.Size,
            "Size mismatch for %s", imageName)
        assert.Equal(t, expected.BrandName, result.BrandName,
            "Brand mismatch for %s", imageName)
        assert.InDelta(t, expected.Price, result.Price, 0.01,
            "Price mismatch for %s", imageName)
    }
}

// Update baseline when intentional changes are made
func TestUpdateBaseline(t *testing.T) {
    if os.Getenv("UPDATE_BASELINE") != "true" {
        t.Skip("Set UPDATE_BASELINE=true to update")
    }

    results := make(map[string]OCRResult)
    testImages := []string{"invoice1.jpg", "invoice2.jpg", "invoice3.jpg"}

    for _, imageName := range testImages {
        imageData := loadTestImage(imageName)
        results[imageName] = extractOCR(imageData)
    }

    saveBaselineResults("testdata/baseline.json", results)
}
```

---

## Testing External APIs

### Pattern 1: Contract Testing

```go
func TestVisionAPI_Contract(t *testing.T) {
    if testing.Short() {
        t.Skip("Skipping API contract test")
    }

    client := setupVisionAPIClient()
    testImage := loadTestImage("simple_text.jpg")

    response, err := client.DetectText(testImage)

    // Verify contract
    assert.NoError(t, err)
    assert.NotNil(t, response)
    assert.NotEmpty(t, response.TextAnnotations)

    // First annotation should be full text
    fullText := response.TextAnnotations[0].Description
    assert.NotEmpty(t, fullText)
}
```

### Pattern 2: Mocking External APIs

```go
func TestOCR_WithMockedAPIs(t *testing.T) {
    // Mock Vision API
    mockVision := &MockVisionAPI{
        Response: "Grey Goose 750ml $29.99",
        Error:    nil,
    }

    // Mock Gemini API
    mockGemini := &MockGeminiAPI{
        Response: "Grey Goose",
        Error:    nil,
    }

    service := NewOCRService(mockVision, mockGemini)
    result := service.ProcessInvoice(testImageData)

    assert.Equal(t, "750ml", result.Size)
    assert.Equal(t, "Grey Goose", result.BrandName)
    assert.Equal(t, 1, mockVision.CallCount)
    assert.Equal(t, 1, mockGemini.CallCount)
}
```

### Pattern 3: Record/Replay

```go
type APIRecorder struct {
    Recording bool
    Replaying bool
    Responses map[string]interface{}
}

func (r *APIRecorder) Call(endpoint string, request interface{}) (interface{}, error) {
    key := generateKey(endpoint, request)

    if r.Replaying {
        // Return recorded response
        if response, ok := r.Responses[key]; ok {
            return response, nil
        }
        return nil, fmt.Errorf("no recorded response for %s", key)
    }

    // Make real API call
    response, err := makeRealAPICall(endpoint, request)

    if r.Recording && err == nil {
        // Record response
        r.Responses[key] = response
    }

    return response, err
}

// Usage
func TestWithRecordedAPI(t *testing.T) {
    recorder := loadRecording("testdata/api_responses.json")
    recorder.Replaying = true

    service := NewOCRServiceWithRecorder(recorder)
    result := service.ProcessInvoice(testImageData)

    assert.Equal(t, "750ml", result.Size)
}
```

---

## Test Data Management

### Strategy 1: Test Data Builders

```go
type OCRResultBuilder struct {
    result *OCRResult
}

func NewOCRResultBuilder() *OCRResultBuilder {
    return &OCRResultBuilder{
        result: &OCRResult{
            ID:        uuid.New(),
            Size:      "750ml",
            BrandName: "Test Brand",
            Price:     29.99,
            Category:  "Vodka",
            Timestamp: time.Now(),
        },
    }
}

func (b *OCRResultBuilder) WithSize(size string) *OCRResultBuilder {
    b.result.Size = size
    return b
}

func (b *OCRResultBuilder) WithBrand(brand string) *OCRResultBuilder {
    b.result.BrandName = brand
    return b
}

func (b *OCRResultBuilder) WithPrice(price float64) *OCRResultBuilder {
    b.result.Price = price
    return b
}

func (b *OCRResultBuilder) Build() *OCRResult {
    return b.result
}

// Usage
func TestValidation(t *testing.T) {
    result := NewOCRResultBuilder().
        WithSize("1175ml").
        WithPrice(39.99).
        Build()

    err := validateOCRResult(result)
    assert.NoError(t, err)
}
```

### Strategy 2: Test Data Fixtures

```go
// testdata/fixtures.go
var TestFixtures = struct {
    ValidInvoice1 []byte
    ValidInvoice2 []byte
    BlurryInvoice []byte
    InvalidInvoice []byte
}{
    ValidInvoice1: loadFixture("valid_invoice_1.jpg"),
    ValidInvoice2: loadFixture("valid_invoice_2.jpg"),
    BlurryInvoice: loadFixture("blurry_invoice.jpg"),
    InvalidInvoice: loadFixture("invalid_invoice.jpg"),
}

// Usage
func TestProcessValidInvoice(t *testing.T) {
    result := extractOCR(TestFixtures.ValidInvoice1)
    assert.Equal(t, "750ml", result.Size)
}
```

---

## CI/CD Integration

### GitHub Actions Workflow

```yaml
name: OCR Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Run unit tests
        run: go test -v -short ./...

      - name: Run integration tests
        run: go test -v -run Integration ./...
        env:
          REDIS_URL: redis://localhost:6379
          DB_URL: postgres://test:test@localhost/test

      - name: Run benchmarks
        run: go test -bench=. -benchmem ./...

      - name: Check coverage
        run: |
          go test -coverprofile=coverage.out ./...
          go tool cover -func=coverage.out
          # Fail if coverage <80%
          coverage=$(go tool cover -func=coverage.out | grep total | awk '{print $3}' | sed 's/%//')
          if (( $(echo "$coverage < 80" | bc -l) )); then
            echo "Coverage is below 80%"
            exit 1
          fi
```

---

## Test Metrics

### Key Metrics to Track

```go
type TestMetrics struct {
    TotalTests       int
    PassedTests      int
    FailedTests      int
    SkippedTests     int
    CodeCoverage     float64
    AvgExecutionTime time.Duration
}

func collectTestMetrics() *TestMetrics {
    // Parse test output and collect metrics
    return &TestMetrics{
        TotalTests:       150,
        PassedTests:      148,
        FailedTests:      2,
        SkippedTests:     0,
        CodeCoverage:     87.5,
        AvgExecutionTime: 2 * time.Second,
    }
}
```

### Coverage Goals

| Component | Target Coverage |
|-----------|----------------|
| Core OCR Logic | >90% |
| API Endpoints | >85% |
| Validation | >95% |
| Cache Layer | >80% |
| Overall | >85% |

---

## Testing Checklist

Before merging code, ensure:

- [ ] All unit tests pass
- [ ] Integration tests pass
- [ ] Code coverage >80%
- [ ] Performance benchmarks don't regress
- [ ] Tests added for new functionality
- [ ] Tests added for bug fixes
- [ ] Edge cases covered
- [ ] Error paths tested
- [ ] Mock external APIs in tests
- [ ] Tests are deterministic (no flaky tests)
- [ ] Tests run in <60 seconds
- [ ] Documentation updated

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0
**Maintained by**: OCR Development Team

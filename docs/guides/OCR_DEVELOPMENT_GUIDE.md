# OCR Development Guide - Practical Handbook

**Purpose**: Hands-on guide for developers working on OCR improvements
**Level**: Beginner to Intermediate
**Prerequisites**: Basic Go knowledge, understanding of OCR concepts

---

## 🎯 Quick Start for New Developers

### Your First Day

**Hour 1: Environment Setup**

```bash
# 1. Navigate to project
cd /var/www/liquorpro

# 2. Verify deployment
./scripts/verify_deployment.sh

# 3. Read essential docs (30 min)
cat README_OCR_IMPROVEMENTS.md
cat OCR_QUICK_REFERENCE.md
```

**Hour 2-3: Understanding the Code**

```bash
# 1. Review main OCR service
code internal/sales/services/ocr_service.go

# 2. Review Gemini client
code pkg/ocr/gemini_client.go

# 3. Study the tests
code internal/sales/services/ocr_service_test.go
```

**Key Files to Know**:
- `internal/sales/services/ocr_service.go:294-354` - Fuzzy size detection
- `internal/sales/services/ocr_service.go:475-570` - Price calculation
- `pkg/ocr/gemini_client.go:142-204` - Brand caching
- `pkg/ocr/gemini_client.go:757-801` - JSON repair

**Hour 4: Run Your First Test**

```bash
# Run all tests
./scripts/ocr_test_runner.sh

# Run specific test
go test -run TestDetectReceiptType ./internal/sales/services

# With verbose output
go test -v -run TestDetectReceiptType ./internal/sales/services
```

---

## 🔧 Common Development Tasks

### Task 1: Adding a New Fuzzy Pattern

**Scenario**: OCR sometimes reads "750ml" as "75Oml" (zero as letter O)

**Step-by-Step**:

1. **Locate the pattern list** (`ocr_service.go:294-354`)

```go
func detectReceiptType(rawText string) string {
    textLower := strings.ToLower(rawText)

    // Find the 750ml patterns section
    size750Patterns := []string{
        `75[0oO]\s*m[\.\s]*l`,  // Existing pattern
        `bottle`,                // Existing alias
    }
    // ...
}
```

2. **Add your new pattern**

```go
size750Patterns := []string{
    `75[0oO]\s*m[\.\s]*l`,      // Handles: 750ml, 75Oml, 75o ml
    `75[0oO]\s*m[l1]`,          // NEW: Also handles 'l' → '1' error
    `bottle`,
}
```

3. **Write a test** (`ocr_service_test.go`)

```go
func TestDetectReceiptType(t *testing.T) {
    tests := []struct {
        name     string
        rawText  string
        expected string
    }{
        // Existing tests...

        // NEW: Your test case
        {
            name:     "Detect 750ml with l→1 OCR error",
            rawText:  "SALE RECEIPT - 75Om1",
            expected: "750ml",
        },
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

4. **Run the test**

```bash
go test -run TestDetectReceiptType ./internal/sales/services
```

5. **Test in production**

```bash
# Monitor for your pattern matching
sudo docker logs liquorpro-sales-prod -f | grep "Fuzzy matched"
```

**Expected Output**:
```
🔧 [OCR] Fuzzy matched 750ml using pattern: 75[0oO]\s*m[l1]
```

---

### Task 2: Adding a New Price Validation Range

**Scenario**: New premium 1000ml bottles range from ₹500-5000

**Step-by-Step**:

1. **Locate validation function** (`ocr_service.go:475-570`)

```go
func validatePriceRange(price float64, receiptType string) bool {
    switch receiptType {
    case "90ml":
        return price >= 40 && price <= 300
    case "180ml":
        return price >= 80 && price <= 500
    case "375ml":
        return price >= 150 && price <= 1000
    case "750ml":
        return price >= 300 && price <= 3000
    // Add new case here
    default:
        return price >= 50 && price <= 2000
    }
}
```

2. **Add your validation**

```go
case "750ml":
    return price >= 300 && price <= 3000
case "1000ml":  // NEW
    return price >= 500 && price <= 5000
default:
    return price >= 50 && price <= 2000
```

3. **Add detection pattern** (in `detectReceiptType`)

```go
// Add 1000ml patterns
size1000Patterns := []string{
    `10[0oO]{2}\s*m[\.\s]*l`,  // Matches: 1000ml, 10OOml, 1000 ml
    `1\s*litre`,                // Alternative: 1 litre
    `1\s*ltr`,                  // Alternative: 1 ltr
}

for _, pattern := range size1000Patterns {
    if matched, _ := regexp.MatchString(pattern, textLower); matched {
        fmt.Printf("🔧 [OCR] Fuzzy matched 1000ml using pattern: %s\n", pattern)
        return "1000ml"
    }
}
```

4. **Write tests**

```go
func TestValidatePriceRange(t *testing.T) {
    tests := []struct {
        name        string
        price       float64
        receiptType string
        expected    bool
    }{
        // NEW: 1000ml tests
        {"1000ml valid low", 500, "1000ml", true},
        {"1000ml valid mid", 2500, "1000ml", true},
        {"1000ml valid high", 5000, "1000ml", true},
        {"1000ml too low", 400, "1000ml", false},
        {"1000ml too high", 5100, "1000ml", false},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := validatePriceRange(tt.price, tt.receiptType)
            if result != tt.expected {
                t.Errorf("Expected %v, got %v", tt.expected, result)
            }
        })
    }
}
```

5. **Run tests and verify**

```bash
# Run validation tests
go test -run TestValidatePriceRange ./internal/sales/services

# Run detection tests
go test -run TestDetectReceiptType ./internal/sales/services
```

---

### Task 3: Improving JSON Repair

**Scenario**: Gemini API sometimes returns JSON with missing closing brackets

**Step-by-Step**:

1. **Locate JSON repair function** (`gemini_client.go:757-801`)

```go
func repairJSON(jsonStr string) string {
    repaired := jsonStr

    // Existing repairs
    // Fix 1: Remove trailing commas
    trailingCommaRegex := regexp.MustCompile(`,(\s*[}\]])`)
    repaired = trailingCommaRegex.ReplaceAllString(repaired, "$1")

    // Fix 2: Unescaped quotes
    // ...

    // Add your new repair here

    return repaired
}
```

2. **Add new repair pattern**

```go
// Fix 7: Add missing closing brackets
// Count opening vs closing brackets
openBraces := strings.Count(repaired, "{")
closeBraces := strings.Count(repaired, "}")
openBrackets := strings.Count(repaired, "[")
closeBrackets := strings.Count(repaired, "]")

// Add missing closing braces
for i := 0; i < openBraces-closeBraces; i++ {
    repaired += "}"
}

// Add missing closing brackets
for i := 0; i < openBrackets-closeBrackets; i++ {
    repaired += "]"
}

fmt.Printf("🔧 [JSON Repair] Added %d closing braces, %d closing brackets\n",
    openBraces-closeBraces, openBrackets-closeBrackets)
```

3. **Add test case**

```go
func TestRepairJSON(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected string
    }{
        // Existing tests...

        // NEW: Missing brackets test
        {
            name:     "Missing closing brackets",
            input:    `{"items": [{"name": "Test", "price": 100}`,
            expected: `{"items": [{"name": "Test", "price": 100}]}`,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := repairJSON(tt.input)

            // Validate it's proper JSON
            var parsed interface{}
            if err := json.Unmarshal([]byte(result), &parsed); err != nil {
                t.Errorf("Repaired JSON is still invalid: %v", err)
            }

            if result != tt.expected {
                t.Errorf("Expected:\n%s\nGot:\n%s", tt.expected, result)
            }
        })
    }
}
```

4. **Test the repair**

```bash
# Run JSON repair tests
go test -run TestRepairJSON ./pkg/ocr
```

5. **Monitor in production**

```bash
sudo docker logs liquorpro-sales-prod -f | grep "JSON Repair"
```

**Expected Output**:
```
🔧 [JSON Repair] Added 1 closing braces, 1 closing brackets
✅ [JSON Repair] Fixed malformed JSON from Gemini API
```

---

## 🐛 Debugging Techniques

### Debugging Failed OCR Extractions

**Problem**: Price extraction failing for certain invoices

**Step 1: Enable verbose logging**

```go
// In ocr_service.go, add detailed logging
func calculatePriceFromRawText(rawText, brandOriginalText string) float64 {
    fmt.Printf("\n=== PRICE DEBUG START ===\n")
    fmt.Printf("Raw Text:\n%s\n", rawText)
    fmt.Printf("Brand Text: %s\n", brandOriginalText)

    receiptType := detectReceiptType(rawText)
    fmt.Printf("Detected Receipt Type: %s\n", receiptType)

    rowMatch := findBrandRow(rawText, brandOriginalText)
    fmt.Printf("Row Match: Found=%v, Score=%d, Row=%s\n",
        rowMatch.Found, rowMatch.MatchScore, rowMatch.Row)

    if !rowMatch.Found {
        fmt.Printf("=== PRICE DEBUG END (no row match) ===\n\n")
        return 0.0
    }

    numbers := extractNumbersFromRow(rowMatch.Row)
    fmt.Printf("Extracted Numbers: %v\n", numbers)

    // Continue with detailed logging...
}
```

**Step 2: Test with real data**

```go
func TestCalculatePriceDebug(t *testing.T) {
    rawText := `
SALE RECEIPT - 90 M.L
Brand Name: Royal Stag
Rate: 150
Quantity: 10
Total: 1500
    `

    price := calculatePriceFromRawText(rawText, "Royal Stag")
    fmt.Printf("Final Price: %.2f\n", price)

    if price != 150.0 {
        t.Errorf("Expected 150.0, got %.2f", price)
    }
}
```

**Step 3: Run with verbose output**

```bash
go test -v -run TestCalculatePriceDebug ./internal/sales/services
```

**Expected Debug Output**:
```
=== PRICE DEBUG START ===
Raw Text:
SALE RECEIPT - 90 M.L
Brand Name: Royal Stag
Rate: 150
Quantity: 10
Total: 1500

Brand Text: Royal Stag
Detected Receipt Type: 90ml
Row Match: Found=true, Score=95, Row=Brand Name: Royal Stag Rate: 150
Extracted Numbers: [150 10 1500]
Final Price: 150.00
=== PRICE DEBUG END ===
```

---

### Debugging Cache Issues

**Problem**: Cache not hitting when expected

**Add cache diagnostics**:

```go
func (c *GeminiClient) NormalizeBrandNameWithCache(ctx context.Context, brandText string) (string, error) {
    cacheKey := strings.ToLower(strings.TrimSpace(brandText))

    c.cacheMutex.RLock()
    entry, exists := c.brandCache[cacheKey]
    c.cacheMutex.RUnlock()

    // ADD: Cache diagnostics
    fmt.Printf("🔍 [Cache Debug] Key='%s', Exists=%v\n", cacheKey, exists)

    if exists {
        age := time.Since(entry.timestamp)
        fmt.Printf("🔍 [Cache Debug] Age=%v, TTL=%v, Valid=%v\n",
            age, c.cacheTTL, age < c.cacheTTL)

        if age < c.cacheTTL {
            fmt.Printf("💨 [Cache HIT] '%s' → '%s' (saved API call)\n",
                brandText, entry.normalizedName)
            return entry.normalizedName, nil
        }

        fmt.Printf("⏰ [Cache EXPIRED] '%s' (age: %v > TTL: %v)\n",
            cacheKey, age, c.cacheTTL)
    }

    // Cache miss or expired - call API
    // ...
}
```

**Monitor cache behavior**:

```bash
# Watch cache hits/misses in real-time
sudo docker logs liquorpro-sales-prod -f | grep "Cache"
```

---

## 🎓 Learning Path

### Week 1: Foundations
- [ ] Read all documentation (INDEX.md → all linked docs)
- [ ] Run verification script successfully
- [ ] Run all tests and understand output
- [ ] Monitor production for 1 hour using ocr_metrics_monitor.sh
- [ ] Study 3 main code files

### Week 2: Hands-On
- [ ] Add one new fuzzy pattern
- [ ] Write 3 new test cases
- [ ] Fix one issue from TROUBLESHOOTING_FAQ.md
- [ ] Review 2 pull requests
- [ ] Run benchmark script and understand results

### Week 3: Advanced
- [ ] Implement one small improvement
- [ ] Add comprehensive tests for your improvement
- [ ] Update documentation
- [ ] Present your changes to team
- [ ] Monitor production impact

---

## 📊 Practical Examples

### Example 1: Complete Feature Addition

**Feature**: Add support for detecting "Half Bottle" as 375ml

**Full Implementation**:

```go
// 1. Add to detectReceiptType (ocr_service.go)
func detectReceiptType(rawText string) string {
    textLower := strings.ToLower(rawText)

    // ... existing patterns ...

    // 375ml patterns
    size375Patterns := []string{
        `375\s*m[\.\s]*l`,
        `37[5s]\s*m[\.\s]*l`,   // Existing
        `half\s*bottle`,         // NEW: Add this
        `1/2\s*bottle`,          // NEW: Add this
    }

    for _, pattern := range size375Patterns {
        if matched, _ := regexp.MatchString(pattern, textLower); matched {
            fmt.Printf("🔧 [OCR] Fuzzy matched 375ml using pattern: %s\n", pattern)
            return "375ml"
        }
    }

    // ... rest of function ...
}

// 2. Add tests (ocr_service_test.go)
func TestDetectReceiptType(t *testing.T) {
    tests := []struct {
        name     string
        rawText  string
        expected string
    }{
        // ... existing tests ...

        // NEW: Half bottle tests
        {
            name:     "Detect 375ml - half bottle",
            rawText:  "SALE RECEIPT - HALF BOTTLE",
            expected: "375ml",
        },
        {
            name:     "Detect 375ml - 1/2 bottle",
            rawText:  "SALE RECEIPT - 1/2 BOTTLE",
            expected: "375ml",
        },
        {
            name:     "Detect 375ml - half bottle lowercase",
            rawText:  "sale receipt - half bottle",
            expected: "375ml",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := detectReceiptType(tt.rawText)
            if result != tt.expected {
                t.Errorf("detectReceiptType(%q) = %q, expected %q",
                    tt.rawText, result, tt.expected)
            }
        })
    }
}

// 3. Update documentation
// Add to CHANGELOG_OCR_IMPROVEMENTS.md:
/*
### Phase 1.3.1: Extended Size Detection (NEW)

**Date**: January 16, 2025

**Change**: Added support for "half bottle" and "1/2 bottle" detection

**Patterns Added**:
- `half\s*bottle` - Matches "half bottle", "half  bottle"
- `1/2\s*bottle` - Matches "1/2 bottle", "1/2  bottle"

**Impact**:
- Improved detection for informal size descriptions
- Handles invoices that don't use standard ml notation

**Test Coverage**: 3 new test cases added
*/
```

**Deployment Checklist**:

```bash
# 1. Run tests
go test -v -run TestDetectReceiptType ./internal/sales/services

# 2. Run full test suite
./scripts/ocr_test_runner.sh

# 3. Check code coverage
go test -coverprofile=coverage.out ./internal/sales/services
go tool cover -func=coverage.out | grep detectReceiptType

# 4. Rebuild container
sudo -E bash -c "set -a; source .env.production 2>/dev/null; set +a; docker compose -f docker-compose.production.yml build sales"

# 5. Deploy
sudo -E bash -c "set -a; source .env.production 2>/dev/null; set +a; docker compose -f docker-compose.production.yml up -d --no-deps sales"

# 6. Verify
./scripts/verify_deployment.sh

# 7. Monitor
./scripts/ocr_metrics_monitor.sh 30
```

---

### Example 2: Debugging a Production Issue

**Scenario**: Users report price extraction failing for "Black Label" brand

**Investigation Process**:

```bash
# 1. Check recent logs for Black Label
sudo docker logs liquorpro-sales-prod --since 1h | grep -i "black label"

# Output might show:
# ❌ [Price] Failed to extract price for 'Black Label'
# 🔍 Row Match: Found=false

# 2. Check if it's a row matching issue
sudo docker logs liquorpro-sales-prod --since 1h | grep -B 5 -A 5 "Black Label"

# 3. Get the raw text that was processed
# (This requires temporarily adding debug logging)
```

**Root Cause**: OCR reading "Black Label" as "B1ack Label" (l→1 error)

**Fix**:

```go
// Improve findBrandRow to be more fuzzy
func findBrandRow(rawText, brandName string) BrandRowMatch {
    lines := strings.Split(rawText, "\n")
    bestMatch := BrandRowMatch{Found: false, MatchScore: 0}

    // Normalize brand name for better matching
    brandNormalized := normalizeBrandForMatching(brandName)

    for _, line := range lines {
        lineNormalized := normalizeBrandForMatching(line)

        // Use fuzzy matching instead of exact match
        score := calculateFuzzyScore(brandNormalized, lineNormalized)

        if score > bestMatch.MatchScore {
            bestMatch = BrandRowMatch{
                Row:        line,
                MatchScore: score,
                Found:      score >= 70, // 70% threshold
            }
        }
    }

    return bestMatch
}

// Helper: Normalize for matching (handles OCR errors)
func normalizeBrandForMatching(text string) string {
    normalized := strings.ToLower(text)
    normalized = strings.ReplaceAll(normalized, "1", "l") // 1→l
    normalized = strings.ReplaceAll(normalized, "0", "o") // 0→o
    normalized = strings.ReplaceAll(normalized, "5", "s") // 5→s
    return normalized
}

// Helper: Calculate fuzzy score
func calculateFuzzyScore(target, candidate string) int {
    // Simple implementation: character match percentage
    matches := 0
    for i := 0; i < len(target) && i < len(candidate); i++ {
        if target[i] == candidate[i] {
            matches++
        }
    }
    if len(target) == 0 {
        return 0
    }
    return (matches * 100) / len(target)
}
```

**Test the fix**:

```go
func TestFindBrandRow_FuzzyMatching(t *testing.T) {
    tests := []struct {
        name          string
        rawText       string
        brandName     string
        expectedFound bool
        minScore      int
    }{
        {
            name: "Exact match",
            rawText: `Line 1
Black Label  Rate: 1500
Line 3`,
            brandName:     "Black Label",
            expectedFound: true,
            minScore:      90,
        },
        {
            name: "OCR error l→1",
            rawText: `Line 1
B1ack Labe1  Rate: 1500
Line 3`,
            brandName:     "Black Label",
            expectedFound: true,
            minScore:      70, // Lower threshold for fuzzy
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := findBrandRow(tt.rawText, tt.brandName)

            if result.Found != tt.expectedFound {
                t.Errorf("Expected Found=%v, got %v", tt.expectedFound, result.Found)
            }

            if result.MatchScore < tt.minScore {
                t.Errorf("Expected score >= %d, got %d", tt.minScore, result.MatchScore)
            }
        })
    }
}
```

---

## 🚀 Quick Reference Commands

### Daily Development

```bash
# Start your day
cd /var/www/liquorpro
git pull
./scripts/verify_deployment.sh

# Run tests while coding
go test -v -run TestYourFunction ./internal/sales/services

# Watch tests continuously
watch -n 2 'go test -run TestYourFunction ./internal/sales/services'

# Check test coverage
go test -cover ./internal/sales/services

# Detailed coverage
go test -coverprofile=coverage.out ./internal/sales/services
go tool cover -html=coverage.out
```

### Debugging

```bash
# Follow logs in real-time
sudo docker logs -f liquorpro-sales-prod

# Search for specific pattern
sudo docker logs liquorpro-sales-prod | grep "YourPattern"

# Check errors in last hour
sudo docker logs liquorpro-sales-prod --since 1h | grep -i error

# Monitor specific improvement
sudo docker logs -f liquorpro-sales-prod | grep "Fuzzy matched"
```

### Testing

```bash
# Run all OCR tests
./scripts/ocr_test_runner.sh

# Run specific test file
go test ./internal/sales/services/ocr_service_test.go

# Run benchmarks
./scripts/ocr_benchmark.sh

# Test with race detection
go test -race ./internal/sales/services
```

---

## 📚 Code Snippets Library

### Snippet 1: Add New Fuzzy Pattern

```go
// In detectReceiptType function
sizeXXXPatterns := []string{
    `YOUR_PATTERN_HERE`,    // Description
    `ALTERNATIVE_PATTERN`,  // Alternative
}

for _, pattern := range sizeXXXPatterns {
    if matched, _ := regexp.MatchString(pattern, textLower); matched {
        fmt.Printf("🔧 [OCR] Fuzzy matched XXXml using pattern: %s\n", pattern)
        return "XXXml"
    }
}
```

### Snippet 2: Add Validation Rule

```go
// In cross-field validation
if brand.YourField /* condition */ {
    result.Issues = append(result.Issues, "Your validation message")
    result.WarningCount++  // or CriticalCount
}
```

### Snippet 3: Add Caching

```go
// Check cache
c.cacheMutex.RLock()
cached, exists := c.yourCache[key]
c.cacheMutex.RUnlock()

if exists && time.Since(cached.timestamp) < c.cacheTTL {
    fmt.Printf("💨 [Cache HIT] '%s'\n", key)
    return cached.value, nil
}

// Update cache after API call
c.cacheMutex.Lock()
c.yourCache[key] = yourCacheEntry{
    value:     result,
    timestamp: time.Now(),
}
c.cacheMutex.Unlock()
```

### Snippet 4: Add Structured Logging

```go
fmt.Printf("🔧 [Component] Action for '%s'\n", item)
fmt.Printf("💨 [Component] Fast path for '%s'\n", item)
fmt.Printf("✅ [Component] Success for '%s'\n", item)
fmt.Printf("⚠️  [Component] Warning for '%s': %s\n", item, warning)
fmt.Printf("❌ [Component] Error for '%s': %v\n", item, err)
```

---

## 🎯 Success Metrics for Developers

After 1 month, you should be able to:

- [ ] Understand all 8 OCR improvements and explain them
- [ ] Write table-driven tests independently
- [ ] Add new fuzzy patterns confidently
- [ ] Debug production issues using logs
- [ ] Review PRs and provide meaningful feedback
- [ ] Contribute at least one improvement

After 3 months, you should be able to:

- [ ] Design and implement new OCR features
- [ ] Optimize performance bottlenecks
- [ ] Mentor new team members
- [ ] Lead technical discussions
- [ ] Propose architectural improvements

---

## 📖 Additional Learning Resources

**Internal Documentation**:
- Start: `README_OCR_IMPROVEMENTS.md`
- Reference: `OCR_QUICK_REFERENCE.md`
- Standards: `BEST_PRACTICES.md`
- Help: `TROUBLESHOOTING_FAQ.md`

**External Resources**:
- Go Testing: https://go.dev/doc/tutorial/add-a-test
- Regular Expressions: https://regex101.com/
- Google Cloud Vision: https://cloud.google.com/vision/docs
- Gemini API: https://ai.google.dev/docs

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0
**Maintainer**: Engineering Team

---

> **Remember**: The best way to learn is by doing. Start small, test thoroughly, and don't be afraid to ask questions!

**Next Steps**: Read `BEST_PRACTICES.md` for detailed standards and `COMMON_PITFALLS.md` for mistakes to avoid.

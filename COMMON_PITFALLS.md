# OCR Common Pitfalls and Solutions

**Purpose**: Learn from common mistakes and avoid them
**Audience**: All developers working on OCR improvements
**Last Updated**: January 15, 2025

---

## 🎯 Overview

This guide documents common mistakes made during OCR development and how to avoid them. Each pitfall includes:

- ❌ **The Mistake**: What developers commonly do wrong
- ⚠️  **Why It's Bad**: The impact and consequences
- ✅ **The Solution**: How to do it correctly
- 📝 **Real Example**: Actual code showing before/after

---

## 📑 Table of Contents

1. [Pattern Matching Pitfalls](#pattern-matching-pitfalls)
2. [Testing Pitfalls](#testing-pitfalls)
3. [Performance Pitfalls](#performance-pitfalls)
4. [Cache Pitfalls](#cache-pitfalls)
5. [Error Handling Pitfalls](#error-handling-pitfalls)
6. [Logging Pitfalls](#logging-pitfalls)
7. [Validation Pitfalls](#validation-pitfalls)
8. [Production Pitfalls](#production-pitfalls)

---

## 🔍 Pattern Matching Pitfalls

### Pitfall 1: Overly Generic Patterns

❌ **The Mistake**:
```go
// Trying to match "90ml" but being too broad
pattern := `.*90.*`
```

⚠️  **Why It's Bad**:
- Matches unwanted text: "190ml", "Price: 900", "Item 90"
- Creates false positives
- Difficult to debug when it matches incorrectly

✅ **The Solution**:
```go
// Be specific about what you're matching
pattern := `9[0oO]\s*m[\.\s]*l`  // Only matches 90ml variations
```

📝 **Real Example**:

**Before (BAD)**:
```go
func detectReceiptType(rawText string) string {
    if strings.Contains(rawText, "90") {
        return "90ml"  // ❌ Matches "Item 90", "Price: 900", etc.
    }
    return "unknown"
}
```

**After (GOOD)**:
```go
func detectReceiptType(rawText string) string {
    textLower := strings.ToLower(rawText)
    size90Patterns := []string{
        `9[0oO]\s*m[\.\s]*l`,  // ✅ Specific pattern
        `nip`,                  // ✅ Known alias only
    }

    for _, pattern := range size90Patterns {
        if matched, _ := regexp.MatchString(pattern, textLower); matched {
            return "90ml"
        }
    }
    return "unknown"
}
```

---

### Pitfall 2: Not Handling OCR Variations

❌ **The Mistake**:
```go
// Looking for exact match only
pattern := `750ml`
```

⚠️  **Why It's Bad**:
- OCR often reads 'l' as '1', '0' as 'O', 'S' as '5'
- Misses valid data due to OCR errors
- Reduces accuracy

✅ **The Solution**:
```go
// Account for common OCR errors
pattern := `75[0oO]\s*m[l1]`  // Handles: 750ml, 75Oml, 75Om1
```

📝 **Real Example**:

**Common OCR Errors to Handle**:
```
Original → OCR Reads As
------------------------
0 → O (letter O)
1 → l (lowercase L) or I
l → 1 or I
S → 5
5 → S
B → 8
8 → B
```

**Pattern Design**:
```go
// ❌ BAD: Exact match only
pattern := `180ml`

// ✅ GOOD: Handles OCR errors
pattern := `[1l][8B][0oO]\s*m[l1]`
// Matches: 180ml, l8Oml, 18Om1, 1BOml, etc.
```

---

### Pitfall 3: Case Sensitivity Issues

❌ **The Mistake**:
```go
// Not normalizing case
if strings.Contains(rawText, "NIP") {
    return "90ml"
}
```

⚠️  **Why It's Bad**:
- Misses "nip", "Nip", "nIP"
- Inconsistent behavior
- Breaks on lowercase input

✅ **The Solution**:
```go
// Always normalize to lowercase first
textLower := strings.ToLower(rawText)
if strings.Contains(textLower, "nip") {
    return "90ml"
}
```

---

## 🧪 Testing Pitfalls

### Pitfall 4: Testing Happy Path Only

❌ **The Mistake**:
```go
func TestDetectReceiptType(t *testing.T) {
    result := detectReceiptType("90ml")
    if result != "90ml" {
        t.Error("Failed")
    }
    // ❌ Only testing one success case
}
```

⚠️  **Why It's Bad**:
- Doesn't catch edge cases
- Misses error conditions
- False confidence in code quality

✅ **The Solution**:
```go
func TestDetectReceiptType(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected string
    }{
        // Happy paths
        {"Standard 90ml", "90ml", "90ml"},
        {"Standard 750ml", "750ml", "750ml"},

        // OCR errors
        {"OCR error 9O", "9Oml", "90ml"},
        {"OCR error 75O", "75Oml", "750ml"},

        // Edge cases
        {"Empty string", "", "unknown"},
        {"Garbage input", "xyz123", "unknown"},
        {"Mixed case", "90ML", "90ml"},

        // Boundary cases
        {"Just number", "90", "unknown"},
        {"Just ml", "ml", "unknown"},
        {"Spacing variations", "90 m l", "90ml"},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := detectReceiptType(tt.input)
            if result != tt.expected {
                t.Errorf("Expected %s, got %s", tt.expected, result)
            }
        })
    }
}
```

---

### Pitfall 5: Poor Test Descriptions

❌ **The Mistake**:
```go
{"test1", input1, expected1},
{"test2", input2, expected2},
{"test3", input3, expected3},
```

⚠️  **Why It's Bad**:
- Can't tell what failed when test breaks
- No documentation of what's being tested
- Hard to maintain

✅ **The Solution**:
```go
{"Detect 90ml with standard format", "SALE RECEIPT - 90 M.L", "90ml"},
{"Detect 90ml with OCR error (0→O)", "SALE RECEIPT - 9O M.L", "90ml"},
{"Detect 90ml using alias (nip)", "SALE RECEIPT - NIP", "90ml"},
```

---

### Pitfall 6: Not Testing Error Conditions

❌ **The Mistake**:
```go
// Only testing successful cases
func TestNormalizeBrand(t *testing.T) {
    result, _ := NormalizeBrand("Royal Stag")  // ❌ Ignoring error
    if result != "ROYAL STAG" {
        t.Error("Failed")
    }
}
```

⚠️  **Why It's Bad**:
- Doesn't verify error handling works
- Production errors surprise you
- No test for failure modes

✅ **The Solution**:
```go
func TestNormalizeBrand(t *testing.T) {
    tests := []struct {
        name        string
        input       string
        expectError bool
        expected    string
    }{
        // Success cases
        {"Valid brand", "Royal Stag", false, "ROYAL STAG"},

        // Error cases
        {"Empty string", "", true, ""},
        {"Only spaces", "   ", true, ""},
        {"Invalid characters", "###", true, ""},
        {"Too long", strings.Repeat("A", 1000), true, ""},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result, err := NormalizeBrand(tt.input)

            if tt.expectError && err == nil {
                t.Error("Expected error but got none")
            }

            if !tt.expectError && err != nil {
                t.Errorf("Unexpected error: %v", err)
            }

            if result != tt.expected {
                t.Errorf("Expected %q, got %q", tt.expected, result)
            }
        })
    }
}
```

---

## ⚡ Performance Pitfalls

### Pitfall 7: Regex in Tight Loops

❌ **The Mistake**:
```go
func processItems(items []string) []string {
    results := []string{}
    for _, item := range items {
        // ❌ Compiling regex on every iteration
        matched, _ := regexp.MatchString(`9[0oO]ml`, item)
        if matched {
            results = append(results, item)
        }
    }
    return results
}
```

⚠️  **Why It's Bad**:
- Regex compilation is expensive
- Happens repeatedly in loop
- Kills performance with many items

✅ **The Solution**:
```go
// Compile regex once, reuse many times
var size90Regex = regexp.MustCompile(`9[0oO]ml`)

func processItems(items []string) []string {
    results := []string{}
    for _, item := range items {
        // ✅ Use pre-compiled regex
        if size90Regex.MatchString(item) {
            results = append(results, item)
        }
    }
    return results
}
```

---

### Pitfall 8: Unnecessary API Calls

❌ **The Mistake**:
```go
func normalizeBrand(brandText string) (string, error) {
    // ❌ Always calling API, even for same input
    return client.NormalizeBrandName(ctx, brandText)
}

// Later:
normalizeBrand("Royal Stag")  // API call
normalizeBrand("Royal Stag")  // API call again! ❌
normalizeBrand("Royal Stag")  // API call again! ❌
```

⚠️  **Why It's Bad**:
- Wastes money (API calls cost money)
- Slow performance (network latency)
- May hit rate limits

✅ **The Solution**:
```go
// Use cache (already implemented in gemini_client.go)
func (c *GeminiClient) NormalizeBrandNameWithCache(ctx context.Context, brandText string) (string, error) {
    cacheKey := strings.ToLower(strings.TrimSpace(brandText))

    // ✅ Check cache first
    c.cacheMutex.RLock()
    entry, exists := c.brandCache[cacheKey]
    c.cacheMutex.RUnlock()

    if exists && time.Since(entry.timestamp) < c.cacheTTL {
        return entry.normalizedName, nil  // ✅ Return cached result
    }

    // Only call API if not cached
    normalized, err := c.NormalizeBrandName(ctx, brandText)
    if err != nil {
        return "", err
    }

    // ✅ Store in cache
    c.cacheMutex.Lock()
    c.brandCache[cacheKey] = brandCacheEntry{
        normalizedName: normalized,
        timestamp:      time.Now(),
    }
    c.cacheMutex.Unlock()

    return normalized, nil
}
```

**Impact**:
- First call: API call (slow, costs money)
- Subsequent calls: Cache hit (fast, free)
- Typical savings: 70% reduction in API calls

---

## 🗄️ Cache Pitfalls

### Pitfall 9: Race Conditions in Cache

❌ **The Mistake**:
```go
type Cache struct {
    data map[string]string  // ❌ No mutex protection
}

func (c *Cache) Get(key string) (string, bool) {
    // ❌ Race condition: multiple goroutines reading/writing
    val, exists := c.data[key]
    return val, exists
}

func (c *Cache) Set(key, value string) {
    // ❌ Race condition: concurrent writes
    c.data[key] = value
}
```

⚠️  **Why It's Bad**:
- Crashes with "concurrent map read and write"
- Data corruption
- Unpredictable behavior in production

✅ **The Solution**:
```go
type Cache struct {
    data  map[string]string
    mutex sync.RWMutex  // ✅ Add mutex protection
}

func (c *Cache) Get(key string) (string, bool) {
    c.mutex.RLock()         // ✅ Read lock
    defer c.mutex.RUnlock()
    val, exists := c.data[key]
    return val, exists
}

func (c *Cache) Set(key, value string) {
    c.mutex.Lock()          // ✅ Write lock
    defer c.mutex.Unlock()
    c.data[key] = value
}
```

---

### Pitfall 10: No Cache Expiration

❌ **The Mistake**:
```go
// ❌ Cache never expires, grows forever
func (c *Cache) Set(key, value string) {
    c.mutex.Lock()
    c.data[key] = value
    c.mutex.Unlock()
}
```

⚠️  **Why It's Bad**:
- Memory leak (cache grows indefinitely)
- Stale data never refreshed
- Eventually runs out of memory

✅ **The Solution**:
```go
type CacheEntry struct {
    value     string
    timestamp time.Time  // ✅ Track when cached
}

type Cache struct {
    data     map[string]CacheEntry
    mutex    sync.RWMutex
    ttl      time.Duration  // ✅ Time-to-live
}

func (c *Cache) Get(key string) (string, bool) {
    c.mutex.RLock()
    entry, exists := c.data[key]
    c.mutex.RUnlock()

    if !exists {
        return "", false
    }

    // ✅ Check if expired
    if time.Since(entry.timestamp) > c.ttl {
        return "", false  // Expired
    }

    return entry.value, true
}

// ✅ Periodic cleanup
func (c *Cache) cleanup() {
    ticker := time.NewTicker(15 * time.Minute)
    for range ticker.C {
        c.mutex.Lock()
        now := time.Now()
        for key, entry := range c.data {
            if now.Sub(entry.timestamp) > c.ttl {
                delete(c.data, key)  // Remove expired entries
            }
        }
        c.mutex.Unlock()
    }
}
```

---

## 🚨 Error Handling Pitfalls

### Pitfall 11: Silently Ignoring Errors

❌ **The Mistake**:
```go
// ❌ Ignoring errors completely
normalized, _ := client.NormalizeBrandName(ctx, brand)
price, _ := calculatePrice(data)
```

⚠️  **Why It's Bad**:
- Silent failures in production
- No visibility into issues
- Corrupts data with zero values

✅ **The Solution**:
```go
// ✅ Handle errors explicitly
normalized, err := client.NormalizeBrandName(ctx, brand)
if err != nil {
    log.Printf("❌ [Normalize] Failed for '%s': %v", brand, err)
    // Decide: return error, use fallback, or continue
    return fallbackNormalization(brand), nil
}

price, err := calculatePrice(data)
if err != nil {
    log.Printf("❌ [Price] Calculation failed: %v", err)
    return 0.0, fmt.Errorf("price calculation failed: %w", err)
}
```

---

### Pitfall 12: Generic Error Messages

❌ **The Mistake**:
```go
if err != nil {
    return fmt.Errorf("error occurred")  // ❌ No context
}
```

⚠️  **Why It's Bad**:
- Can't debug production issues
- No context about what failed
- Wastes debugging time

✅ **The Solution**:
```go
if err != nil {
    return fmt.Errorf("failed to normalize brand '%s': %w", brandText, err)
}

if price <= 0 {
    return fmt.Errorf("invalid price %.2f for brand '%s' (type: %s)",
        price, brandName, receiptType)
}
```

---

## 📝 Logging Pitfalls

### Pitfall 13: Logging Too Much

❌ **The Mistake**:
```go
func processItem(item string) {
    fmt.Println("Starting processItem")
    fmt.Println("Item:", item)
    fmt.Println("Length:", len(item))
    fmt.Println("Checking condition 1")
    // ... 50 more log lines ...
    fmt.Println("Done")
}
```

⚠️  **Why It's Bad**:
- Log flooding makes important messages invisible
- Performance impact
- Expensive log storage costs

✅ **The Solution**:
```go
func processItem(item string) {
    // ✅ Log only important events
    fmt.Printf("🔧 [Process] Processing item: %s\n", item)

    // Process...

    if err != nil {
        fmt.Printf("❌ [Process] Failed for '%s': %v\n", item, err)
    } else {
        fmt.Printf("✅ [Process] Success for '%s'\n", item)
    }
}
```

---

### Pitfall 14: No Structured Logging

❌ **The Mistake**:
```go
fmt.Println("Price is", price, "for", brand, "type", receiptType)
// Output: Price is 150 for Royal Stag type 90ml
// ❌ Hard to parse, search, or filter
```

⚠️  **Why It's Bad**:
- Can't grep/filter logs effectively
- No visual hierarchy
- Hard to debug

✅ **The Solution**:
```go
fmt.Printf("💰 [Price] Direct extraction - Rate column: %.2f (brand: %s, type: %s)\n",
    price, brand, receiptType)
// Output: 💰 [Price] Direct extraction - Rate column: 150.00 (brand: Royal Stag, type: 90ml)
// ✅ Easy to search: grep "Price" | grep "Royal Stag"
```

**Log Format Standard**:
```
{emoji} [Component] Action - Details (context)

Examples:
🔧 [OCR] Fuzzy matched 90ml using pattern: 9[0oO]ml
💨 [Cache HIT] 'Royal Stag' → 'ROYAL STAG' (saved API call)
✅ [Validation] All checks passed (brand: Black Label)
⚠️  [Validation] Found 2 warnings (brand: XYZ)
❌ [Price] Extraction failed for 'ABC' (type: 750ml)
```

---

## ✅ Validation Pitfalls

### Pitfall 15: Validation Too Strict

❌ **The Mistake**:
```go
func validatePrice(price float64, receiptType string) bool {
    // ❌ Extremely narrow range
    if receiptType == "90ml" {
        return price == 150  // Only accepts exactly 150
    }
    return false
}
```

⚠️  **Why It's Bad**:
- Rejects valid data
- Prices vary by brand/region
- Reduces accuracy instead of improving it

✅ **The Solution**:
```go
func validatePriceRange(price float64, receiptType string) bool {
    switch receiptType {
    case "90ml":
        return price >= 40 && price <= 300  // ✅ Reasonable range
    case "750ml":
        return price >= 300 && price <= 3000
    default:
        return price >= 50 && price <= 2000
    }
}
```

---

### Pitfall 16: Validation Too Loose

❌ **The Mistake**:
```go
func validatePrice(price float64) bool {
    return price > 0  // ❌ Accepts any positive number
}

// Accepts: 0.01, 999999, etc.
```

⚠️  **Why It's Bad**:
- Doesn't catch obvious errors
- Price of 1 rupee for 750ml bottle? Clearly wrong
- No value from validation

✅ **The Solution**:
```go
func validatePrice(price float64, receiptType string) bool {
    // ✅ Reasonable bounds based on actual market prices
    switch receiptType {
    case "90ml":
        return price >= 40 && price <= 300
    case "180ml":
        return price >= 80 && price <= 500
    case "375ml":
        return price >= 150 && price <= 1000
    case "750ml":
        return price >= 300 && price <= 3000
    default:
        return price >= 50 && price <= 2000  // Sensible default
    }
}
```

---

## 🚀 Production Pitfalls

### Pitfall 17: Not Testing in Production

❌ **The Mistake**:
```go
// Deploy changes without monitoring
git push origin main
// Walk away ❌
```

⚠️  **Why It's Bad**:
- Don't know if changes work in production
- Issues discovered days later
- Blame is unclear

✅ **The Solution**:
```bash
# Deploy
sudo -E bash -c "set -a; source .env.production 2>/dev/null; set +a; docker compose -f docker-compose.production.yml up -d --no-deps sales"

# ✅ Monitor immediately (at least 30 min)
./scripts/ocr_metrics_monitor.sh 30

# ✅ Check for errors
sudo docker logs liquorpro-sales-prod --since 5m | grep -i error

# ✅ Verify your improvement is working
sudo docker logs liquorpro-sales-prod -f | grep "YourImprovement"
```

---

### Pitfall 18: No Rollback Plan

❌ **The Mistake**:
```go
// Deploy new version
docker-compose up -d

// New version has critical bug
// ❌ No way to quickly revert
```

⚠️  **Why It's Bad**:
- Production broken with no quick fix
- Scrambling to debug under pressure
- Extended downtime

✅ **The Solution**:
```bash
# Before deploying, tag current working version
docker tag liquorpro/sales:latest liquorpro/sales:backup-2025-01-15

# Deploy new version
docker-compose up -d

# If it fails, rollback immediately
docker tag liquorpro/sales:backup-2025-01-15 liquorpro/sales:latest
docker-compose up -d --force-recreate sales

# ✅ Back to working state in <1 minute
```

---

### Pitfall 19: Changing Too Much At Once

❌ **The Mistake**:
```go
// In one commit:
// - Add 5 new fuzzy patterns
// - Change price validation logic
// - Refactor cache system
// - Update API integration
// Deploy all at once ❌
```

⚠️  **Why It's Bad**:
- If something breaks, can't isolate what caused it
- Risky to rollback (loses all changes)
- Hard to review

✅ **The Solution**:
```bash
# Deploy incrementally:

# Step 1: Add fuzzy patterns (low risk)
git commit -m "Add 2 new size detection patterns"
# Deploy + Monitor 1 hour

# Step 2: Update validation (medium risk)
git commit -m "Adjust 90ml price validation range"
# Deploy + Monitor 2 hours

# Step 3: Cache changes (higher risk)
git commit -m "Implement brand cache with 1-hour TTL"
# Deploy + Monitor 4 hours

# ✅ If Step 2 fails, can rollback without losing Step 1
```

---

## 📊 Real-World Pitfall Examples

### Example 1: The "Works on My Machine" Bug

**Scenario**: Developer tests locally, works fine. Deploys to production, breaks.

**Root Cause**:
```go
// Local testing with small dataset (10 items)
items := []string{"90ml", "750ml", ...}  // Works fine

// Production with 10,000 items
// ❌ Regex compiled 10,000 times in loop (slow)
// ❌ No cache warming (cold start performance)
// ❌ Memory usage not tested at scale
```

**Solution**:
1. Test with production-sized data
2. Use production environment for final testing
3. Monitor performance metrics

---

### Example 2: The Cache Stampede

**Scenario**: All cache entries expire at same time. Hundreds of API calls hit simultaneously.

**Root Cause**:
```go
// ❌ All entries cached at startup with same TTL
for _, brand := range brands {
    cache.Set(brand, normalized, 1*time.Hour)  // All expire together
}
```

**Solution**:
```go
// ✅ Add jitter to TTL
ttl := 1*time.Hour + time.Duration(rand.Intn(300))*time.Second
cache.Set(brand, normalized, ttl)  // Expire at different times
```

---

### Example 3: The Silent Failure

**Scenario**: OCR accuracy drops from 95% to 70%. No one notices for a week.

**Root Cause**:
- No monitoring alerts
- Errors logged but not reviewed
- No automated accuracy tracking

**Solution**:
```bash
# Set up daily monitoring
crontab -e

# Add:
0 9 * * * /var/www/liquorpro/scripts/ocr_metrics_monitor.sh 60 | mail -s "Daily OCR Report" team@example.com
```

---

## ✅ Quick Prevention Checklist

Before merging any code:

- [ ] Tests include edge cases and error conditions
- [ ] Patterns are specific, not generic
- [ ] Case normalization applied to all text matching
- [ ] Errors are handled explicitly (no `_` ignoring)
- [ ] Logging is structured with emojis and context
- [ ] Regex patterns compiled once (not in loops)
- [ ] Cache has mutex protection and expiration
- [ ] Validation ranges are sensible (not too strict/loose)
- [ ] Changes are small and focused
- [ ] Rollback plan exists
- [ ] Production monitoring plan ready

---

## 📚 Learning from Mistakes

**Good Practice**:
1. When you find a bug, add a test for it
2. Document the pitfall (add to this document)
3. Share with team (lunch & learn)
4. Update best practices if needed

**Example**:
```go
// Bug found: Didn't handle nil pointer when brand text is empty
func TestNormalizeBrand_EmptyInput(t *testing.T) {
    // Regression test for bug #123
    result, err := NormalizeBrand("")
    if err == nil {
        t.Error("Expected error for empty input")
    }
}
```

---

## 🎯 Summary

**Most Common Pitfalls**:
1. 🔍 Generic regex patterns → Be specific
2. 🧪 Only testing happy path → Test edges and errors
3. ⚡ Regex in loops → Compile once, reuse
4. 🗄️ No cache protection → Use mutexes
5. 🚨 Ignoring errors → Handle explicitly
6. 📝 Poor logging → Structure with context
7. ✅ Wrong validation ranges → Based on real data
8. 🚀 Not monitoring after deploy → Always monitor

**Golden Rules**:
- ✅ Test with real production data
- ✅ Start simple, add complexity only when needed
- ✅ Monitor every deployment
- ✅ Handle errors explicitly
- ✅ Log with structure and context

---

**Remember**: Everyone makes mistakes. The key is to learn from them and share the knowledge!

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0
**Contribute**: Found a new pitfall? Add it to this document!

**Related Docs**:
- `BEST_PRACTICES.md` - What to do
- `OCR_DEVELOPMENT_GUIDE.md` - How to do it
- `TROUBLESHOOTING_FAQ.md` - When things go wrong

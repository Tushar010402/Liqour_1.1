# OCR Code Review Checklist

**Purpose**: Ensure high-quality code through consistent review standards
**Use**: Check off items when reviewing pull requests
**Last Updated**: January 15, 2025

---

## 🎯 How to Use This Checklist

**For Reviewers**:
1. Copy this checklist into PR comments
2. Check off items as you review
3. Add comments for any issues found
4. Approve only when all critical items pass

**For Authors**:
1. Self-review using this checklist before requesting review
2. Include test results in PR description
3. Address all reviewer comments

---

## ✅ General Code Quality

### Code Structure
- [ ] Functions are <100 lines (ideally <50)
- [ ] Functions have single, clear purpose
- [ ] No code duplication
- [ ] No commented-out code
- [ ] No debug statements or temporary code
- [ ] Proper indentation and formatting

### Naming
- [ ] Variables have descriptive names (`normalizedBrand` not `nb`)
- [ ] Constants are used for magic numbers
- [ ] Function names clearly describe what they do
- [ ] No cryptic abbreviations

### Comments & Documentation
- [ ] Complex logic has explanatory comments
- [ ] Comments explain "why", not "what"
- [ ] Public functions have documentation
- [ ] No TODO comments without ticket references
- [ ] Updated relevant documentation files

---

## 🔍 OCR-Specific Checks

### Pattern Matching
- [ ] Patterns are specific, not overly generic
- [ ] OCR error variations are handled (0→O, 1→l, etc.)
- [ ] Case normalization applied (`strings.ToLower()`)
- [ ] Regex patterns compiled once (not in loops)
- [ ] Pattern descriptions included in comments

**Example Check**:
```go
// ✅ GOOD
size90Patterns := []string{
    `9[0oO]\s*m[\.\s]*l`,  // Handles: 90ml, 9Oml, 9o m.l
    `nip`,                  // Common alias
}

// ❌ BAD
pattern := `.*90.*`  // Too generic
```

### Fuzzy Matching
- [ ] Fuzzy patterns account for common OCR errors
- [ ] Pattern list is comprehensive but not excessive
- [ ] Each pattern has a comment explaining what it matches
- [ ] Test cases cover all pattern variations

### Fallback Logic
- [ ] Multiple extraction methods tried in order
- [ ] Clear success/failure indicators
- [ ] Each fallback logged appropriately
- [ ] Final fallback returns sensible default

**Example Check**:
```go
// ✅ GOOD
if price, ok := extractFromRate(data); ok {
    return price
}
if price, ok := extractFromCalculation(data); ok {
    return price
}
return 0.0  // Clear failure

// ❌ BAD
price := complexExtractionLogic(data)  // Unclear if succeeded
```

---

## 🧪 Testing

### Test Coverage
- [ ] New code has >90% test coverage
- [ ] Modified code maintains >80% coverage
- [ ] Critical paths have 100% coverage
- [ ] All tests pass locally

### Test Quality
- [ ] Uses table-driven test pattern
- [ ] Tests have clear, descriptive names
- [ ] Tests cover happy path, edge cases, and error conditions
- [ ] Tests are independent (no shared state)
- [ ] Tests clean up after themselves

### Test Cases Include
- [ ] Happy path (expected inputs)
- [ ] Edge cases (empty, nil, boundary values)
- [ ] Error conditions (invalid inputs)
- [ ] OCR variations (common misreads)
- [ ] Performance cases (if applicable)

**Example Check**:
```go
// ✅ GOOD
tests := []struct {
    name     string
    input    string
    expected string
}{
    {"Standard 90ml", "90 M.L", "90ml"},           // Happy
    {"OCR error", "9O M.L", "90ml"},                // OCR variation
    {"Empty", "", "unknown"},                       // Edge
    {"Invalid", "xyz", "unknown"},                  // Error
}

// ❌ BAD
if detectReceiptType("90ml") != "90ml" {
    t.Error("failed")  // Only one case, unclear what's tested
}
```

---

## ⚡ Performance

### Efficiency
- [ ] No unnecessary loops or iterations
- [ ] Regex compiled once and reused
- [ ] Database queries optimized (if applicable)
- [ ] Cache used where appropriate
- [ ] No blocking operations in hot path

### Resource Usage
- [ ] No memory leaks (cache has expiration)
- [ ] Large allocations justified
- [ ] String concatenation uses `strings.Builder` for loops
- [ ] Files/connections closed properly

**Example Check**:
```go
// ✅ GOOD - Compiled once
var size90Regex = regexp.MustCompile(`9[0oO]ml`)

func process(items []string) {
    for _, item := range items {
        if size90Regex.MatchString(item) { ... }
    }
}

// ❌ BAD - Compiled in loop
func process(items []string) {
    for _, item := range items {
        matched, _ := regexp.MatchString(`9[0oO]ml`, item)
    }
}
```

---

## 🗄️ Caching

### Cache Implementation
- [ ] Cache has mutex/RWMutex protection
- [ ] Cache entries have expiration (TTL)
- [ ] Cache has periodic cleanup
- [ ] Cache key normalization (lowercase, trim)
- [ ] Cache hit/miss logged appropriately

### Cache Safety
- [ ] No race conditions
- [ ] Proper read/write lock usage
- [ ] Cache size bounds (if needed)
- [ ] Stale data handling

**Example Check**:
```go
// ✅ GOOD
type Cache struct {
    data  map[string]CacheEntry
    mutex sync.RWMutex  // ✅ Thread-safe
    ttl   time.Duration // ✅ Has expiration
}

// ❌ BAD
type Cache struct {
    data map[string]string  // ❌ No mutex, no expiration
}
```

---

## 🚨 Error Handling

### Error Handling
- [ ] All errors handled explicitly (no `_` ignoring)
- [ ] Error messages include context
- [ ] Errors wrapped with `fmt.Errorf(..., %w, err)`
- [ ] Appropriate error logging level
- [ ] Fallback behavior for recoverable errors

### Error Messages
- [ ] Descriptive (includes relevant variables)
- [ ] Structured (consistent format)
- [ ] Actionable (hints at solution)
- [ ] Not exposing sensitive data

**Example Check**:
```go
// ✅ GOOD
normalized, err := client.NormalizeBrand(brandText)
if err != nil {
    return "", fmt.Errorf("failed to normalize brand '%s': %w", brandText, err)
}

// ❌ BAD
normalized, _ := client.NormalizeBrand(brandText)  // Ignoring error
```

---

## 📝 Logging

### Log Quality
- [ ] Structured format: `{emoji} [Component] Action - Details`
- [ ] Appropriate emoji for log level
- [ ] Includes relevant context (brand, size, etc.)
- [ ] No sensitive data in logs
- [ ] Not too verbose (no log flooding)

### Log Levels (by emoji)
- [ ] 🔧 Info - Normal operations
- [ ] 💨 Debug - Cache hits, optimization paths
- [ ] ✅ Success - Validations passed, operations completed
- [ ] ⚠️  Warning - Recoverable issues
- [ ] ❌ Error - Failures that need attention

**Example Check**:
```go
// ✅ GOOD
fmt.Printf("🔧 [OCR] Fuzzy matched %s using pattern: %s\n", result, pattern)
fmt.Printf("❌ [Price] Extraction failed for '%s': %v\n", brand, err)

// ❌ BAD
fmt.Println("Processing")  // No context
log.Debug(data)  // Raw data dump
```

---

## ✅ Validation

### Validation Logic
- [ ] Validation ranges are based on real data
- [ ] Not too strict (rejects valid data)
- [ ] Not too loose (accepts invalid data)
- [ ] Edge cases handled (nil, empty, zero)
- [ ] Validation failures logged with context

### Cross-Field Validation
- [ ] Related fields checked for consistency
- [ ] Warning vs critical issues distinguished
- [ ] Validation results logged
- [ ] Business rules enforced

**Example Check**:
```go
// ✅ GOOD - Reasonable ranges
switch receiptType {
case "90ml":
    return price >= 40 && price <= 300  // Based on market data

// ❌ BAD - Too strict
case "90ml":
    return price == 150  // Only one value

// ❌ BAD - Too loose
return price > 0  // Accepts 0.01
```

---

## 🔒 Security & API Usage

### API Safety
- [ ] API keys not hardcoded
- [ ] API calls have error handling
- [ ] API calls have timeout
- [ ] Rate limiting considered
- [ ] API responses validated before use

### Data Privacy
- [ ] No PII in logs
- [ ] Sensitive data not cached
- [ ] User data handled per privacy policy

---

## 📚 Documentation

### Code Documentation
- [ ] README updated if needed
- [ ] CHANGELOG updated with changes
- [ ] API documentation updated
- [ ] Inline code comments for complex logic

### Guide Updates
- [ ] New patterns added to documentation
- [ ] Best practices updated if needed
- [ ] Troubleshooting guide updated for new issues
- [ ] Quick reference updated if applicable

---

## 🚀 Deployment Readiness

### Pre-Deployment
- [ ] All tests pass
- [ ] Coverage meets requirements (>80%)
- [ ] No linting warnings
- [ ] Performance benchmarks run (if applicable)
- [ ] Changes reviewed by at least one other developer

### Deployment Plan
- [ ] Rollback plan documented
- [ ] Monitoring plan in place
- [ ] Incremental deployment if high-risk
- [ ] On-call schedule clear

### Post-Deployment
- [ ] Plan to monitor for at least 30 minutes
- [ ] Metrics to watch identified
- [ ] Error alerting configured
- [ ] Team notified of deployment

---

## 📋 PR Description Checklist

**Author should include**:
- [ ] What: Clear description of changes
- [ ] Why: Reason for changes / problem being solved
- [ ] How: High-level approach
- [ ] Testing: Test results and coverage
- [ ] Deployment: Any special deployment notes
- [ ] Monitoring: What to watch after deployment
- [ ] Screenshots: If UI changes
- [ ] Related: Links to related issues/PRs

---

## 🎯 Review Severity Levels

### 🔴 Critical (Must Fix)
- Security vulnerabilities
- Data corruption risks
- Production-breaking changes
- Race conditions
- Resource leaks

### 🟡 Important (Should Fix)
- Performance issues
- Missing error handling
- Poor test coverage
- Code duplication
- Unclear naming

### 🟢 Minor (Nice to Have)
- Code style inconsistencies
- Comment improvements
- Refactoring opportunities
- Documentation enhancements

---

## ✅ Final Approval Checklist

Before approving PR:

- [ ] All critical items pass
- [ ] All important items addressed or have justification
- [ ] Tests added and passing
- [ ] Documentation updated
- [ ] No security concerns
- [ ] Performance acceptable
- [ ] Code is maintainable
- [ ] Ready for production

---

## 📝 Review Comment Templates

### Requesting Changes
```
❌ Issue: [Describe the problem]

Location: [File:line]

Why: [Explain why it's a problem]

Suggestion:
```[language]
[Your suggested fix]
```

Severity: [Critical/Important/Minor]
```

### Suggesting Improvements
```
💡 Suggestion: [Your idea]

Current approach works, but we could improve by:
[Your suggestion]

Benefits: [Why this is better]

Optional: This can be done in a follow-up PR
```

### Asking Questions
```
❓ Question: [Your question]

I'm not sure I understand [specific part]. Could you explain:
- [Question 1]
- [Question 2]

This will help me review more effectively.
```

### Approving
```
✅ LGTM (Looks Good To Me)

Changes reviewed:
- ✅ Code quality
- ✅ Tests comprehensive
- ✅ Documentation updated
- ✅ No security concerns

Approved for merge.

Reminder: Monitor after deployment!
```

---

## 🔄 Common Review Scenarios

### Scenario 1: New Fuzzy Pattern

**Must Check**:
- [ ] Pattern is specific enough
- [ ] Handles OCR variations
- [ ] Has descriptive comment
- [ ] Test cases cover all variations
- [ ] Won't match unintended text

**Example Review**:
```go
// Code:
size90Patterns := []string{
    `9[0oO]ml`,  // NEW pattern added
}

// ✅ Review Questions:
// 1. Does it handle spacing? (90 ml, 90ml)
// 2. Does it handle dots? (90 m.l)
// 3. Is there a test for "9Oml" (zero as O)?

// 💡 Suggestion:
size90Patterns := []string{
    `9[0oO]\s*m[\.\s]*l`,  // Better: handles spacing and dots
}
```

### Scenario 2: Price Validation Change

**Must Check**:
- [ ] New range is data-driven
- [ ] Not too strict (rejecting valid prices)
- [ ] Not too loose (accepting invalid prices)
- [ ] Test cases at boundaries
- [ ] Documentation updated

**Review Comments**:
```
❓ Question: What data is this range based on?

Current change:
case "90ml":
    return price >= 50 && price <= 250

Could you share:
1. Data source for these ranges
2. How many valid prices would be rejected by old range
3. How many invalid prices would be accepted by new range
```

### Scenario 3: Cache Implementation

**Must Check**:
- [ ] Thread-safe (has mutex)
- [ ] Has expiration (TTL)
- [ ] Has cleanup mechanism
- [ ] Read/write locks used correctly
- [ ] Cache key normalization

**Critical Review**:
```
🔴 Critical: Race condition

Location: cache.go:45

Code:
val := c.data[key]  // ❌ No mutex protection

Issue: Concurrent access to map will cause panic

Fix:
c.mutex.RLock()
val := c.data[key]
c.mutex.RUnlock()

This must be fixed before merge.
```

---

## 🎓 For New Reviewers

**Start Here**:
1. Review the `BEST_PRACTICES.md` guide
2. Read `COMMON_PITFALLS.md` for what to watch for
3. Use this checklist for every review
4. Ask questions - it's okay to not know everything
5. Start with smaller PRs to build confidence

**Review Tips**:
- Take your time - thorough review prevents bugs
- Ask questions if unclear
- Be specific in comments
- Suggest solutions, don't just point out problems
- Approve only when you'd be comfortable maintaining the code

---

## 📊 Review Metrics

**Good Review Should**:
- Take 15-30 minutes (depending on PR size)
- Find at least 1-2 improvement opportunities
- Ask 1-2 clarifying questions
- Provide actionable feedback
- Balance criticism with praise

**Red Flags** (needs more scrutiny):
- PR >500 lines changed
- No tests added
- Documentation not updated
- Multiple unrelated changes
- Rushed timeline

---

## 🏆 Review Best Practices

1. **Review promptly** - Within 24 hours
2. **Be constructive** - Suggest improvements, don't just criticize
3. **Explain reasoning** - Help author learn
4. **Test the code** - Don't just read it
5. **Check the full impact** - Think about production
6. **Approve confidently** - Only when you're sure it's ready

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0

**Related Resources**:
- `BEST_PRACTICES.md` - Coding standards
- `COMMON_PITFALLS.md` - What to avoid
- `OCR_DEVELOPMENT_GUIDE.md` - Development guide
- `TROUBLESHOOTING_FAQ.md` - Common issues

---

> **Remember**: Code review is about collaboration, not criticism. We're all working together to build great software!

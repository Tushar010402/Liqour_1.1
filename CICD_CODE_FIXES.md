# CI/CD Code Quality Fixes Required

## Issues Found by go vet:

### 1. FullName() Function Not Called
**Files affected:**
- `internal/finance/services/cash_service.go` (lines: 462, 489, 563, 606, 891, 918, 998, 1041)

**Issue:** `FullName` is a method but not being called
```go
// ❌ Wrong:
fmt.Errorf("error from %s", fromUser.FullName)

// ✅ Correct:
fmt.Errorf("error from %s", fromUser.FullName())
```

**Fix:** Add `()` to all FullName references

### 2. Lock Copying Issues
**Files affected:**
- `pkg/caching/distributed_cache.go` (lines: 363, 386)
- `pkg/featureflags/feature_flags.go` (line: 484)

**Issue:** Copying struct with mutex (causes deadlocks)
```go
// ❌ Wrong:
metrics := c.metrics  // copies the mutex

// ✅ Correct:
metrics := &c.metrics  // use pointer
```

### 3. Type Mismatches
**Files affected:**
- `scripts/seed_catalog/main.go` (line: 80)
- `test/data/test_data_manager.go` (line: 147)

**Quick fixes needed**

---

## Quick Fix Script

Run this to fix the main issues:

```bash
# Fix FullName() calls
sed -i '' 's/fromUser\.FullName/fromUser.FullName()/g' internal/finance/services/cash_service.go
sed -i '' 's/requestedFrom\.FullName/requestedFrom.FullName()/g' internal/finance/services/cash_service.go
sed -i '' 's/collection\.FromUser\.FullName/collection.FromUser.FullName()/g' internal/finance/services/cash_service.go
sed -i '' 's/request\.RequestedFrom\.FullName/request.RequestedFrom.FullName()/g' internal/finance/services/cash_service.go

# Verify fix
go vet ./internal/finance/services/cash_service.go
```

# Deprecated Functions - Removal Timeline

This document tracks deprecated functions and their migration paths. All deprecated functions are scheduled for removal in v2.0.

## v2.0 Removal Target

### auth/services/tenant_service.go

| Deprecated Function | Replacement | Notes |
|---------------------|-------------|-------|
| `GetSalesmanShopID()` | `utils.GetUserShopAccess()` | Provides better multi-shop support |

### pkg/shared/models/finance.go

| Deprecated Field | Replacement | Notes |
|------------------|-------------|-------|
| `BalanceBefore` | `PreviousBalance` | Consistent naming convention |
| `BalanceAfter` | `NewBalance` | Consistent naming convention |
| `RelatedType` | `RelatedEntityType` | More descriptive field name |
| `RelatedID` | `RelatedEntityID` | More descriptive field name |
| `SubmittedAmount` | `TotalAmount` | Clearer semantics |

### finance/services/assistant_manager_service.go

| Deprecated Pattern | Migration Path | Notes |
|--------------------|----------------|-------|
| `ExecutiveID` field | Use new service pattern | Legacy field from old schema |

## Migration Guide

### Step 1: Update Function Calls

Replace deprecated function calls with their new equivalents:

```go
// Before (deprecated)
shopID := tenantService.GetSalesmanShopID(userID)

// After
shopAccess := utils.GetUserShopAccess(ctx, userID)
```

### Step 2: Update Model References

Update field references in your code:

```go
// Before (deprecated)
transaction.BalanceBefore = previousBalance
transaction.BalanceAfter = newBalance

// After
transaction.PreviousBalance = previousBalance
transaction.NewBalance = newBalance
```

### Step 3: Database Migration

A database migration script will be provided to rename columns. Ensure you run the migration before upgrading to v2.0.

## Timeline

| Version | Action |
|---------|--------|
| v1.5.0 | Deprecation warnings added |
| v1.6.0 | Migration guide published |
| v2.0.0 | Deprecated functions removed |

## Questions?

Contact the backend team for migration assistance.

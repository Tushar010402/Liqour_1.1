# Finance Workflow

## Overview

The finance workflow covers cash collection, expenses, vendor payments, and reconciliation.

---

## 1. Cash Collection Workflow

### 1.1 The Collection Deadline (Configurable)

The collection deadline is **configurable per tenant** via `TenantSettings.MoneyCollectionDeadlineMinutes`. The default is **15 minutes**.

```
Sales Approved
     │
     ├── 0 min: Collection window opens
     │
     ├── Warning: Notification at configured warning time
     │
     ├── Deadline: Configured deadline (default: 15 min)
     │
     └── After: Escalation to Manager (overdue status)
```

### 1.2 Process

1. Daily sales approved by manager (`POST /api/daily-records/:id/approve`)
2. System creates MoneyCollection record (status: `pending`)
3. Deadline timer starts based on tenant settings
4. Asst. Manager collects cash (`POST /api/money-collections/:id/collect`)
5. Collection recorded (status: `collected`)
6. Manager approves collection (status: `approved`)
7. Deadline compliance tracked

---

## 2. Expense Workflow

### 2.1 Process

1. Employee submits expense
2. Attach receipt (required for most)
3. Manager reviews
4. Approve or reject
5. Expense recorded
6. Included in daily reconciliation

### 2.2 Approval Limits

| Amount | Approver |
|--------|----------|
| < ₹500 | Auto-approve (with receipt) |
| ₹500-5,000 | Manager |
| > ₹5,000 | Admin |

---

## 3. Vendor Payment Workflow

### 3.1 Process

1. Create payment record
2. Select vendor and amount
3. Enter payment method
4. Add reference number
5. Submit
6. Ledger updated

---

## 4. Daily Reconciliation

### 4.1 Process

1. End of day triggered
2. System calculates expected cash
3. Manager enters actual count
4. Variance calculated
5. Explanation required if variance
6. Day closed

### 4.2 Reconciliation Formula

```
Opening Float
+ Cash Sales
- Cash Expenses
- Bank Deposits
= Expected Closing
```

---

## 5. Bank Deposit Workflow

### 5.1 Process

1. Manager prepares deposit
2. Records deposit in system
3. Enters reference number
4. Bank account updated
5. Reconciled with statement

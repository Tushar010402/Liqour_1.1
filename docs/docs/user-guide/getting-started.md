# Getting Started with LiquorPro

## Welcome to LiquorPro!

This guide will help you get started with LiquorPro, the comprehensive liquor shop management platform. Whether you're a salesman, manager, or administrator, this guide covers everything you need to begin using the system effectively.

---

## 1. System Requirements

### 1.1 Mobile App Requirements

| Platform | Minimum Version |
|----------|----------------|
| **iOS** | iOS 13.0 or later |
| **Android** | Android 8.0 (API 26) or later |

### 1.2 Admin Panel Requirements

| Browser | Minimum Version |
|---------|----------------|
| Chrome | Version 90+ |
| Safari | Version 14+ |
| Firefox | Version 88+ |
| Edge | Version 90+ |

---

## 2. Account Setup

### 2.1 First-Time Registration

1. **Download the App**
    - iOS: Search "LiquorPro" in App Store
    - Android: Search "LiquorPro" in Play Store

2. **Open the App** and tap **"Register"**

3. **Request OTP**
    - Enter your phone number
    - Tap "Send OTP"

4. **Verify OTP**
    - Enter the 6-digit OTP sent to your phone
    - OTP is valid for **10 minutes**
    - Maximum 3 verification attempts

5. **Enter Your Details**
    - Full Name
    - Email (optional)
    - Business/Tenant Name (for admin registration)

6. **Wait for Approval**
    - Your administrator will assign you to a shop
    - You'll receive a notification when approved

### 2.2 Logging In (OTP-Only Authentication)

LiquorPro uses **OTP-only authentication** - no passwords required!

1. Open the LiquorPro app
2. Enter your registered phone number
3. Tap **"Login"**
4. Enter the 6-digit OTP sent to your phone
5. You're now logged in!

!!! info "Device Information"
    Your device is automatically registered for session management. LiquorPro tracks device fingerprints for security.

!!! tip "Session Management"
    LiquorPro allows login on maximum 2 devices simultaneously. Logging in on a third device will automatically log out your oldest session.

---

## 3. Understanding Your Role

LiquorPro uses a 6-level role hierarchy where higher levels inherit all permissions from lower levels:

```
Owner (Level 6) → Admin (Level 5) → Manager (Level 4) → Assistant Manager (Level 3) → Executive (Level 2) → Salesman (Level 1)
```

### 3.1 Salesman (Level 1)

**What you can do:**
- Enter daily sales records
- Process sales returns
- View your sales history
- Upload receipt images for OCR
- View product catalog and prices

**Dashboard View:**
```
┌─────────────────────────────────────┐
│        Today's Sales Summary        │
├─────────────────────────────────────┤
│  Total Sales: ₹45,000               │
│  Items Sold: 35                     │
│  Pending Approval: 1                │
├─────────────────────────────────────┤
│  [+ New Daily Sales]                │
│  [View Sales History]               │
│  [Upload Receipts]                  │
└─────────────────────────────────────┘
```

### 3.2 Executive (Level 2)

**Additional capabilities:**
- View sales reports
- View financial summaries
- Monitor team performance

### 3.3 Assistant Manager (Level 3)

**Additional capabilities:**
- Collect cash from salesmen
- Approve daily sales (limited)
- Approve expenses (limited)
- View shop reports

!!! warning "15-Minute Rule"
    As an Assistant Manager, you must collect cash from approved daily sales within **15 minutes** of approval. Failure to do so will trigger an alert to the Manager and mark the collection as overdue.

### 3.4 Manager (Level 4)

**Additional capabilities:**
- Approve/reject daily sales
- Manage shop inventory
- View financial reports
- Manage shop staff (users, salesmen)

### 3.5 Admin (Level 5)

**Additional capabilities:**
- Manage all shops in tenant
- Create and manage all users
- Configure tenant settings
- Revert approved transactions
- Access all reports and analytics

### 3.6 Owner (Level 6)

**Full platform access:**
- All Admin capabilities
- Platform-level configuration
- Cross-tenant visibility (if applicable)
- System-wide settings

---

## 4. Navigation Guide

### 4.1 Mobile App Navigation

```
┌─────────────────────────────────────┐
│            LiquorPro                │
├─────────────────────────────────────┤
│                                     │
│         [Main Content Area]         │
│                                     │
├─────────────────────────────────────┤
│  🏠      📊      ➕      📦      👤  │
│ Home  Dashboard  Add   Inventory Profile│
└─────────────────────────────────────┘
```

**Bottom Navigation:**

| Icon | Tab | Description |
|------|-----|-------------|
| 🏠 | Home | Dashboard and quick actions |
| 📊 | Dashboard | Sales analytics and reports |
| ➕ | Add | Quick add for sales/expenses |
| 📦 | Inventory | Product and stock management |
| 👤 | Profile | Account settings and logout |

### 4.2 Key Screens

1. **Home Screen**
    - Today's summary
    - Pending tasks
    - Quick actions

2. **Daily Sales**
    - Bulk entry grid
    - Draft management
    - Submission status

3. **Inventory**
    - Product catalog
    - Stock levels
    - Low stock alerts

4. **Reports**
    - Sales reports
    - Financial summaries
    - Export options

---

## 5. Quick Start: Your First Day

### 5.1 For Salesmen

#### Step 1: Start Your Day
1. Open the app and log in
2. Check the **Home** screen for any notifications
3. Review yesterday's pending items (if any)

#### Step 2: Enter Daily Sales
1. Tap **"+ New Daily Sales"**
2. Select today's date (should be pre-selected)
3. Start adding products sold:
    - Search for product by name
    - Enter quantity sold
    - Price is auto-filled
    - Add discount if applicable
4. Continue adding all products
5. Tap **"Save as Draft"** periodically
6. When complete, tap **"Submit for Approval"**

#### Step 3: Track Your Submission
1. Go to **Dashboard** > **My Submissions**
2. Check status: Draft, Pending, Approved, or Rejected
3. If rejected, view reason and resubmit

### 5.2 For Managers

#### Step 1: Review Pending Approvals
1. Open the app
2. Check the **"Pending Approvals"** section on Home
3. Tap on a pending record to review

#### Step 2: Approve or Reject
1. Review the daily sales details
2. Verify amounts and quantities
3. Tap **"Approve"** or **"Reject"**
4. Add comments if needed
5. Monitor the 15-minute collection deadline

#### Step 3: Monitor Shop Performance
1. Go to **Dashboard**
2. Review daily/weekly/monthly trends
3. Check for low stock alerts
4. Review pending purchase orders

---

## 6. Essential Features

### 6.1 Daily Sales Entry (Bulk Grid)

The bulk entry grid is designed to save time:

```
┌──────────────────────────────────────────────────────────┐
│ Daily Sales - January 11, 2025                           │
├──────────────────────────────────────────────────────────┤
│ Product          │ Qty  │ Price   │ Discount │ Total     │
├──────────────────┼──────┼─────────┼──────────┼───────────┤
│ 🔍 Search...     │      │         │          │           │
├──────────────────┼──────┼─────────┼──────────┼───────────┤
│ Royal Challenge  │ 10   │ ₹450    │ ₹0       │ ₹4,500    │
│ Blenders Pride   │ 5    │ ₹550    │ ₹50      │ ₹2,700    │
│ McDowell's No.1  │ 20   │ ₹320    │ ₹0       │ ₹6,400    │
├──────────────────┼──────┼─────────┼──────────┼───────────┤
│                           TOTAL   │          │ ₹13,600   │
├──────────────────────────────────────────────────────────┤
│ [Save Draft]                        [Submit for Approval]│
└──────────────────────────────────────────────────────────┘
```

**Tips:**
- Use product search to quickly find items
- Prices are auto-filled from the catalog
- Save drafts frequently to avoid data loss
- Only submit when all entries are complete

### 6.2 OCR Receipt Processing

Upload receipt images to automatically extract sales data:

1. Tap **"Upload Receipts"**
2. Select multiple receipt images
3. Wait for AI processing
4. Review extracted data
5. Correct any errors
6. Confirm and save

!!! note "OCR Accuracy"
    The AI extraction is typically 85-95% accurate. Always review extracted data before saving.

### 6.3 Stock Checking

Before making sales entries, check stock availability:

1. Go to **Inventory** tab
2. Search for product
3. View current stock level
4. Check reorder level status

---

## 7. Common Tasks

### 7.1 Adding a Daily Sales Record

```
1. Home → + New Daily Sales
2. Verify date and shop
3. Add products:
   - Search product → Enter quantity → Auto-calculate
   - Repeat for all products
4. Add expenses (if any):
   - Transport, packaging, etc.
5. Review total
6. Submit for approval
```

### 7.2 Processing a Sales Return

```
1. Dashboard → Sales History
2. Find the original sale
3. Tap → Process Return
4. Select items being returned
5. Enter return reason
6. Confirm return
7. Stock automatically adjusted
```

### 7.3 Checking Stock Levels

```
1. Inventory → Stocks
2. Filter by shop (if multiple)
3. View stock levels
4. Red = Below reorder level
5. Tap product for details
```

### 7.4 Approving Daily Sales (Managers)

```
1. Home → Pending Approvals
2. Tap record to review
3. Check:
   - Product quantities
   - Prices correct
   - Total matches
4. Tap Approve or Reject
5. Add comments if needed
```

---

## 8. Tips for Success

### 8.1 Daily Best Practices

| Time | Action |
|------|--------|
| Morning | Check pending tasks and notifications |
| Throughout Day | Save drafts frequently |
| End of Day | Submit daily sales before leaving |
| Evening | Review approval status |

### 8.2 Common Mistakes to Avoid

!!! danger "Avoid These Mistakes"
    1. **Not saving drafts** - Data can be lost if app closes
    2. **Wrong quantities** - Double-check before submission
    3. **Missing discounts** - Include all discounts given
    4. **Delayed submission** - Submit before end of day
    5. **Ignoring notifications** - Important alerts need attention

### 8.3 Keyboard Shortcuts (Admin Panel)

| Shortcut | Action |
|----------|--------|
| `Ctrl + S` | Save draft |
| `Ctrl + Enter` | Submit |
| `/` | Search |
| `Esc` | Close dialog |
| `?` | Show help |

---

## 9. Getting Help

### 9.1 In-App Help

- Tap the **?** icon for contextual help
- Access tutorials from Profile → Help
- View FAQs in the Help section

### 9.2 Contact Support

- **Email**: support@liquorpro.io
- **Phone**: +91-XXXX-XXXXXX
- **Hours**: Monday-Saturday, 9 AM - 6 PM IST

### 9.3 Report Issues

1. Go to Profile → Report Issue
2. Describe the problem
3. Attach screenshots if helpful
4. Submit

---

## 10. Next Steps

Now that you're set up, explore these guides:

- [Role Journeys](role-journeys.md) - Detailed workflows for each role
- [Daily Operations](daily-operations.md) - Detailed workflow guide
- [Sales Management](sales-management.md) - Complete sales guide
- [Inventory Management](inventory-management.md) - Stock management
- [Reports & Analytics](reports.md) - Understanding your data
- [Troubleshooting](troubleshooting.md) - Common issues and solutions

---

!!! success "You're Ready!"
    You now have the basics to start using LiquorPro. As you use the system, you'll discover more features designed to make your work easier and more efficient.

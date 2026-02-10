# User Access Module (Authentication)

Controls who can log in and what they can do - like the keys and locks for your shop.

---

## What This Module Does

The User Access Module handles everything about user identity and permissions:

| Capability | What It Means For You |
|------------|----------------------|
| **User Registration** | New staff can create accounts |
| **Login** | Secure access to the system |
| **Permissions** | Control what each person can do |
| **Session Management** | Track who's logged in and where |
| **Security** | Protect against unauthorized access |

---

## Key Features

### 1. User Registration

**What it is:** How new team members get accounts.

#### Registration Options

| Method | Best For |
|--------|----------|
| **Phone Number** | Primary method - quick and verified |
| **Email** | Alternative method with email verification |
| **Invited by Admin** | Staff members added by managers |

#### What Happens When Someone Registers

1. Enter phone number or email
2. Receive verification code (OTP)
3. Enter the code
4. Set up profile (name, role)
5. Account ready to use!

#### Account Types

| Type | Who Creates It | Purpose |
|------|----------------|---------|
| **Owner Account** | Shop owner during signup | Full control of business |
| **Staff Account** | Admin/Manager | Employees with specific roles |
| **Multi-Shop Admin** | Owner | Manages multiple locations |

---

### 2. Login & Verification

**What it is:** How users prove their identity.

#### Login Methods

| Method | How It Works |
|--------|--------------|
| **Phone + OTP** | Enter phone, receive code, enter code |
| **Email + Password** | Traditional username/password |
| **Remember Me** | Stay logged in on trusted devices |

#### Security Features

| Feature | What It Does |
|---------|--------------|
| **OTP Verification** | One-time codes prevent password theft |
| **Session Timeout** | Auto logout after inactivity |
| **Device Tracking** | See all devices with access |
| **Login Alerts** | Get notified of new logins |

#### Session Limits

| Role | Max Active Sessions | Reason |
|------|---------------------|--------|
| Owner | 5 | Access from multiple places |
| Manager | 3 | Office, home, mobile |
| Cashier | 1 | One terminal at a time |
| Delivery | 1 | Mobile only |

---

### 3. User Roles & Permissions

**What it is:** Who can do what in LiquorPro.

#### Default Roles

| Role | Description | Typical Permissions |
|------|-------------|---------------------|
| **Owner** | Business owner | Everything - full control |
| **Admin** | System administrator | User management, settings, reports |
| **Manager** | Store manager | Daily operations, inventory, staff |
| **Accountant** | Financial role | Finance, reports, reconciliation |
| **Cashier** | Sales staff | Billing, basic returns |
| **Stock Keeper** | Inventory staff | Stock management, receiving |
| **Delivery** | Delivery personnel | Deliveries, payment collection |

#### Permission Categories

##### Sales Permissions

| Permission | Owner | Admin | Manager | Cashier |
|------------|-------|-------|---------|---------|
| Create Sale | Yes | Yes | Yes | Yes |
| Apply Discount | Yes | Yes | Yes | Limited |
| Large Discount (>20%) | Yes | Yes | Approval | No |
| Process Return | Yes | Yes | Yes | Basic |
| Void Sale | Yes | Yes | Yes | No |
| Credit Sale | Yes | Yes | Yes | With limit |

##### Inventory Permissions

| Permission | Owner | Admin | Manager | Stock Keeper |
|------------|-------|-------|---------|--------------|
| View Stock | Yes | Yes | Yes | Yes |
| Receive Stock | Yes | Yes | Yes | Yes |
| Adjust Stock | Yes | Yes | Yes | With reason |
| Transfer Stock | Yes | Yes | Yes | No |
| Write-off | Yes | Yes | Approval | No |

##### Financial Permissions

| Permission | Owner | Admin | Accountant | Manager |
|------------|-------|-------|------------|---------|
| View Reports | Yes | Yes | Yes | Limited |
| Cash Management | Yes | Yes | Yes | Yes |
| Bank Reconciliation | Yes | Yes | Yes | No |
| Credit Limits | Yes | Yes | Yes | View only |
| Financial Settings | Yes | Yes | No | No |

##### Admin Permissions

| Permission | Owner | Admin | Manager |
|------------|-------|-------|---------|
| Add Users | Yes | Yes | No |
| Edit Roles | Yes | Yes | No |
| System Settings | Yes | Yes | No |
| View Audit Logs | Yes | Yes | Limited |
| Delete Data | Yes | Limited | No |

---

### 4. Device Management

**What it is:** Control which devices can access accounts.

#### Features

| Feature | What It Does |
|---------|--------------|
| **Device List** | See all devices logged into each account |
| **Remote Logout** | End sessions on lost/stolen devices |
| **Device Naming** | Label devices for easy identification |
| **Trust Settings** | Mark devices as trusted/untrusted |

#### Device Information Tracked

| Data | Purpose |
|------|---------|
| Device Name | "John's iPhone" |
| Last Active | Know when device was last used |
| Location | General area (city level) |
| Session Start | When this login happened |

---

### 5. Security Features

**What it is:** Protecting your business from unauthorized access.

#### Security Measures

| Feature | How It Protects You |
|---------|---------------------|
| **Encrypted Data** | All information sent securely |
| **OTP Expiry** | Codes only valid for 5 minutes |
| **Failed Login Limits** | Account locked after 5 wrong attempts |
| **Activity Logs** | Complete record of who did what |
| **Suspicious Login Detection** | Alerts for unusual access patterns |

#### Password/PIN Requirements

| Requirement | Details |
|-------------|---------|
| Minimum Length | 6 characters |
| Complexity | At least 1 number |
| No Common Words | Blocked patterns like "123456" |
| Change Frequency | Recommended every 90 days |

---

## User Workflows

### New Staff Onboarding

```
1. Admin clicks "Add Staff"
          │
          ▼
2. Enter staff details
   - Name, phone, email
   - Select role
          │
          ▼
3. Staff receives invitation
   (SMS/Email with link)
          │
          ▼
4. Staff clicks link
   - Verifies phone
   - Sets password/PIN
          │
          ▼
5. Account active!
   Ready to work
```

### Forgot Password/PIN

```
1. Click "Forgot Password"
          │
          ▼
2. Enter registered phone
          │
          ▼
3. Receive OTP
          │
          ▼
4. Enter OTP
          │
          ▼
5. Set new password/PIN
          │
          ▼
6. All sessions logged out
   (Security measure)
```

### Managing Staff Access

```
1. Go to Settings → Users
          │
          ▼
2. Select staff member
          │
          ▼
3. Options available:
   - Edit permissions
   - Change role
   - Reset password
   - Disable account
   - View activity
```

---

## Business Benefits

### For Owners

| Benefit | How |
|---------|-----|
| **Control** | Set exactly what each person can do |
| **Accountability** | Know who did every action |
| **Security** | Prevent theft and unauthorized changes |
| **Flexibility** | Adjust permissions as business grows |

### For Managers

| Benefit | How |
|---------|-----|
| **Delegation** | Give staff appropriate access |
| **Oversight** | Monitor staff activity |
| **Quick Onboarding** | Add new staff in minutes |
| **Easy Offboarding** | Instant access removal |

### For Staff

| Benefit | How |
|---------|-----|
| **Simple Login** | OTP - no passwords to remember |
| **Clear Access** | Know exactly what you can do |
| **Multiple Devices** | Work from different devices |
| **Quick Recovery** | Easy password/PIN reset |

---

## Success Metrics

| Metric | Target | Why It Matters |
|--------|--------|---------------|
| **Login Success Rate** | > 99% | Users can access system |
| **OTP Delivery Time** | < 30 seconds | Quick verification |
| **Session Security** | Zero breaches | Protected business |
| **Onboarding Time** | < 5 minutes | Quick staff setup |

---

## Common Questions

### "What if a staff member leaves?"

1. Go to Settings → Users
2. Find the staff member
3. Click "Disable Account"
4. All their sessions end immediately
5. They can no longer access LiquorPro

### "Can I limit what a cashier can discount?"

Yes! You can set:
- Maximum discount percentage (e.g., 10%)
- Discounts above that need manager approval
- Complete discount blocking for specific roles

### "How do I see what someone did?"

1. Go to Reports → Activity Logs
2. Filter by user name
3. See all their actions with timestamps
4. Filter by action type if needed

### "What happens if someone tries too many wrong passwords?"

- After 3 failed attempts: Warning shown
- After 5 failed attempts: Account locked for 15 minutes
- Owner/Admin can manually unlock if needed

### "Can the same person have access to multiple shops?"

Yes! Multi-shop access allows:
- Single login for all locations
- Different roles per location possible
- Consolidated view of all shops

---

## Related Documentation

- [User Guide - Getting Started](../../user-guide/getting-started.md)
- [Security Overview](../../system/security.md)
- [Multi-Shop Management](tenant-module.md)

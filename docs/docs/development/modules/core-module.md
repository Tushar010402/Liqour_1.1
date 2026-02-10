# Core Module

The foundation that keeps LiquorPro running smoothly - like the electrical system and plumbing in a building.

---

## What This Module Does

The Core Module handles all the "invisible" work that makes LiquorPro reliable:

| Capability | What It Means For You |
|------------|----------------------|
| **System Configuration** | Settings that control how LiquorPro behaves |
| **Data Storage** | Safely stores all your business information |
| **Performance** | Makes everything fast and responsive |
| **Error Handling** | Catches problems before they affect you |
| **Activity Tracking** | Records what happens for troubleshooting |

---

## Key Features

### 1. Configuration Management

**What it is:** The control panel for LiquorPro settings.

#### Business Benefits

| Feature | Benefit |
|---------|---------|
| **Environment Settings** | Different settings for testing vs. real business use |
| **Feature Switches** | Turn features on/off for specific shops without restarting |
| **Customization** | Adjust system behavior without technical help |

#### Feature Switches (Examples)

You can enable or disable specific features for each shop:

| Feature | When You Might Turn It Off |
|---------|---------------------------|
| Credit Sales | For cash-only locations |
| Loyalty Points | During system transition |
| Auto Reorder | When managing stock manually |
| Advanced Reports | For basic subscription plans |

---

### 2. Data Storage & Safety

**What it is:** How your business data is stored and protected.

#### Business Benefits

| Feature | What It Means |
|---------|---------------|
| **Always Available** | System keeps working even if one server has issues |
| **Fast Access** | Frequently used data loads instantly |
| **Data Safety** | Your information is never lost, even during outages |
| **Automatic Backups** | Data saved regularly without any action needed |

#### What Gets Stored

| Data Type | Examples |
|-----------|----------|
| Transactions | Every sale, return, payment |
| Products | Your entire catalog with prices |
| Customers | Contact info, purchase history, credit |
| Inventory | Stock levels at every location |
| Reports | Historical data for analysis |

---

### 3. Performance Features

**What it is:** Technology that keeps LiquorPro fast.

#### How It Works (Simple Terms)

| Feature | What It Does |
|---------|--------------|
| **Smart Memory** | Remembers frequently accessed data so it loads instantly |
| **Efficient Processing** | Handles multiple users without slowing down |
| **Load Balancing** | Spreads work across servers so nothing gets overloaded |

#### Performance Targets

| Metric | Target |
|--------|--------|
| Page Load Time | Under 1 second |
| Transaction Processing | Under 3 seconds |
| Report Generation | Under 10 seconds |
| System Availability | 99.9% uptime |

---

### 4. Error Handling

**What it is:** How the system prevents and recovers from problems.

#### What This Means For You

| Situation | How LiquorPro Handles It |
|-----------|-------------------------|
| **Network Issue** | Works offline, syncs when connected |
| **Invalid Input** | Shows helpful error message, doesn't crash |
| **System Overload** | Queues requests, processes them in order |
| **Hardware Problem** | Automatically switches to backup server |

#### Error Messages

When something goes wrong, you'll see clear messages like:

| Error Type | Message Example |
|------------|-----------------|
| Validation | "Please enter a valid phone number" |
| Stock Issue | "Only 5 units available, 10 requested" |
| Credit Limit | "Customer has exceeded credit limit of Rs.5,000" |
| Connection | "Working offline - changes will sync when connected" |

---

### 5. Activity Tracking

**What it is:** Recording what happens in the system for security and troubleshooting.

#### What Gets Tracked

| Activity | Why It's Tracked |
|----------|-----------------|
| User Logins | Security monitoring |
| Sales Transactions | Audit trail |
| Stock Changes | Accountability |
| Settings Changes | Change management |
| System Errors | Quick troubleshooting |

#### Who Can See What

| Role | Can View |
|------|----------|
| Owner | Everything |
| Admin | User activity, system events |
| Manager | Sales and inventory logs |
| Accountant | Financial transaction logs |

---

## How It Supports Your Business

### Daily Operations

| Need | How Core Module Helps |
|------|----------------------|
| "Is the system working?" | Health monitoring shows green/red status |
| "Why is it slow?" | Performance metrics pinpoint issues |
| "What happened yesterday?" | Activity logs show all events |
| "Can I try a new feature?" | Feature switches let you test safely |

### Business Intelligence

| Need | How Core Module Helps |
|------|----------------------|
| "How busy is the system?" | Usage metrics show peak times |
| "Are we growing?" | Historical data shows trends |
| "Who did what?" | Complete audit trail |

---

## Module Dependencies

```
┌─────────────────────────────────────────────┐
│              CORE MODULE                     │
│                                              │
│  ┌──────────────┐  ┌──────────────┐         │
│  │ Configuration│  │ Data Storage │         │
│  └──────────────┘  └──────────────┘         │
│                                              │
│  ┌──────────────┐  ┌──────────────┐         │
│  │ Performance  │  │ Error Handling│        │
│  └──────────────┘  └──────────────┘         │
│                                              │
│  ┌──────────────┐                           │
│  │Activity Logs │                           │
│  └──────────────┘                           │
└─────────────────────────────────────────────┘
            │
            ▼
    All Other Modules Depend on Core
```

---

## Success Metrics

How we measure if the Core Module is working well:

| Metric | Target | Why It Matters |
|--------|--------|---------------|
| **Uptime** | 99.9% | System always available |
| **Response Time** | < 200ms | Fast user experience |
| **Error Rate** | < 0.1% | Reliable operations |
| **Data Consistency** | 100% | No lost or corrupted data |

---

## Common Questions

### "Why is the system sometimes slow?"

The Core Module monitors performance. Slowness could be due to:
- High traffic during peak hours
- Large report generation
- Network issues

### "How often is data backed up?"

- Real-time: Every transaction is immediately saved
- Hourly: Full system snapshot
- Daily: Complete backup stored offsite

### "Can I customize system settings?"

Yes, through the Admin panel:
- Business hours
- Receipt formats
- Notification preferences
- Feature toggles

### "What happens during maintenance?"

- Planned: You'll be notified in advance
- System continues in limited mode
- No data is lost

---

## Related Documentation

- [System Architecture](../../system/overview.md) - Overall system design
- [Security Module](../../system/security.md) - Security features
- [Infrastructure](../../system/infrastructure.md) - Hardware and hosting

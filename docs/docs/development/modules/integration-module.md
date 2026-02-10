# Integration Module (Connect Other Systems)

Connect LiquorPro with other software you use.

---

## What This Module Does

The Integration Module connects LiquorPro with external systems:

| Capability | What It Means For You |
|------------|----------------------|
| **Accounting Sync** | Auto-sync with Tally, QuickBooks |
| **Payment Gateways** | Accept online payments |
| **Communication** | SMS/WhatsApp integration |
| **E-commerce** | Sync with online stores |

---

## Available Integrations

### 1. Accounting Software

**What it is:** Sync financial data with your accounting system.

#### Supported Systems

| System | What Syncs |
|--------|------------|
| **Tally** | Sales, purchases, payments |
| **QuickBooks** | Invoices, expenses, customers |
| **Zoho Books** | Transactions, inventory |
| **Busy** | Vouchers, ledgers |

#### How It Works

```
LiquorPro generates data
         │
         ▼
Format converted automatically
         │
         ▼
Sent to accounting system
         │
         ▼
Books updated in real-time
```

---

### 2. Payment Gateways

**What it is:** Accept digital payments.

#### Supported Gateways

| Gateway | Payment Types |
|---------|---------------|
| **Razorpay** | Cards, UPI, Wallets |
| **Paytm** | UPI, Wallet |
| **PhonePe** | UPI |
| **Google Pay** | UPI |

#### Features

| Feature | Benefit |
|---------|---------|
| **QR Code** | Customer scans to pay |
| **Payment Link** | Send via SMS/WhatsApp |
| **Auto Reconciliation** | Payments matched automatically |
| **Refund Processing** | Easy refund handling |

---

### 3. Communication

**What it is:** Send messages to customers.

#### SMS Features

| Feature | Use Case |
|---------|----------|
| **Receipts** | Send digital bill via SMS |
| **Payment Reminders** | Remind customers to pay |
| **Promotions** | Announce offers |
| **OTP** | Login verification |

#### WhatsApp Features

| Feature | Use Case |
|---------|----------|
| **Digital Receipts** | Rich format bills |
| **Order Updates** | Delivery status |
| **Two-way Chat** | Customer support |
| **Catalog Share** | Product information |

---

### 4. E-commerce

**What it is:** Connect with online sales channels.

#### Supported Platforms

| Platform | Integration Type |
|----------|------------------|
| **Custom Website** | Direct API |
| **Swiggy Instamart** | Order sync |
| **Dunzo** | Delivery integration |

#### What Syncs

| Data | Direction |
|------|-----------|
| Products | LiquorPro → Online |
| Prices | LiquorPro → Online |
| Stock | LiquorPro → Online |
| Orders | Online → LiquorPro |

---

### 5. Hardware Integration

**What it is:** Connect physical devices.

#### Supported Devices

| Device | Purpose |
|--------|---------|
| **Barcode Scanner** | Product scanning |
| **Receipt Printer** | Print bills |
| **Cash Drawer** | Auto-open on sale |
| **Label Printer** | Print price tags |
| **Weighing Scale** | Weight-based items |

---

### 6. Data Export

**What it is:** Export data to other systems.

#### Export Options

| Format | Use Case |
|--------|----------|
| **Excel** | Analysis, reporting |
| **CSV** | Data import elsewhere |
| **PDF** | Documents, reports |
| **Google Sheets** | Cloud-based analysis |

#### Scheduled Exports

- Daily sales export
- Weekly inventory
- Monthly reports
- Custom schedules

---

## Setting Up Integrations

### General Process

```
1. Go to Settings → Integrations
         │
         ▼
2. Select Integration
         │
         ▼
3. Enter Credentials
   (API keys, accounts)
         │
         ▼
4. Configure Options
   (What to sync, frequency)
         │
         ▼
5. Test Connection
         │
         ▼
6. Enable Integration
```

### Managing Integrations

| Action | How |
|--------|-----|
| **Enable/Disable** | Toggle switch |
| **View Logs** | See sync history |
| **Manual Sync** | Force immediate sync |
| **Edit Settings** | Change configuration |

---

## Business Benefits

### For Owners

| Benefit | How |
|---------|-----|
| **Less Manual Work** | Auto-sync data |
| **Fewer Errors** | No re-typing |
| **Time Savings** | Instant updates |
| **Better Insights** | Combined data |

### For Accountants

| Benefit | How |
|---------|-----|
| **Real-time Books** | Always updated |
| **Accurate Data** | No entry errors |
| **Easy Reconciliation** | Data matches |

### For Staff

| Benefit | How |
|---------|-----|
| **Easy Communication** | One-click messages |
| **Hardware Support** | Devices just work |
| **Less Training** | Familiar tools |

---

## Success Metrics

| Metric | Target | Why It Matters |
|--------|--------|---------------|
| **Sync Success Rate** | > 99% | Reliable transfers |
| **Sync Latency** | < 5 minutes | Near real-time |
| **Error Rate** | < 0.1% | Accurate data |

---

## Common Questions

### "How do I connect Tally?"

1. Go to Settings → Integrations → Tally
2. Enter Tally company details
3. Configure sync options
4. Test connection
5. Enable auto-sync

### "Can I send receipts on WhatsApp?"

Yes! During sale:
1. Add customer phone number
2. Complete sale
3. Click "Send WhatsApp Receipt"
Or enable auto-send in settings

### "What if an integration fails?"

- System retries automatically
- Failed items shown in log
- Manual retry option available
- Alerts for repeated failures

### "Can I use multiple payment gateways?"

Yes! Configure all you need:
- Each can be enabled/disabled
- Customer chooses at checkout
- All reconciled in one place

---

## Related Documentation

- [Finance Module](finance-module.md) - Payment reconciliation
- [Sales Module](sales-module.md) - POS integration
- [Reports Module](reports-module.md) - Export options

# Inventory Module (Stock Management)

Track every bottle from when it arrives to when it's sold - never lose track of your stock.

---

## What This Module Does

The Inventory Module manages everything about your products and stock:

| Capability | What It Means For You |
|------------|----------------------|
| **Product Catalog** | Complete list of everything you sell |
| **Real-Time Stock** | Always know what's in stock |
| **Low Stock Alerts** | Never run out unexpectedly |
| **Purchase Orders** | Order from suppliers efficiently |
| **Stock Adjustments** | Handle breakage, theft, and discrepancies |

---

## Key Features

### 1. Product Catalog

**What it is:** Your complete product database.

#### Product Information

| Field | Example |
|-------|---------|
| **Name** | Johnnie Walker Black Label |
| **Brand** | Johnnie Walker |
| **Category** | Whiskey > Scotch |
| **Size** | 750ml |
| **MRP** | Rs. 2,800 |
| **Your Price** | Rs. 2,650 |
| **Barcode** | 5000267024301 |
| **HSN Code** | 22083020 |

#### Product Features

| Feature | Benefit |
|---------|---------|
| **Images** | Visual identification |
| **Multiple Sizes** | Same product, different bottles |
| **Price Tiers** | Retail, wholesale, special |
| **Tax Settings** | GST rates configured |

---

### 2. Stock Tracking

**What it is:** Real-time view of all your inventory.

#### Stock Information

| What You See | Why It Matters |
|--------------|----------------|
| **Current Quantity** | What's available right now |
| **On Order** | What's coming from suppliers |
| **Reserved** | Held for pending orders |
| **Available** | Actually sellable |

#### Stock by Location

For multi-shop businesses:
- See stock at each shop
- Transfer between locations
- Combined total view

---

### 3. Receiving Stock

**What it is:** Record products coming in from suppliers.

#### Receiving Process

```
1. Supplier delivers goods
         │
         ▼
2. Create Goods Receipt
   - Select supplier
   - Enter invoice details
         │
         ▼
3. Add Products
   - Scan or search
   - Enter quantities
   - Verify prices
         │
         ▼
4. Quality Check
   - Check for damage
   - Verify expiry dates
         │
         ▼
5. Complete Receipt
   - Stock updated
   - Invoice recorded
```

#### What Gets Recorded

| Information | Purpose |
|-------------|---------|
| Supplier invoice number | Reference |
| Invoice date | Payment terms |
| Products and quantities | Stock update |
| Purchase price | Cost tracking |
| Expiry dates | FIFO management |

---

### 4. Stock Alerts

**What it is:** Automatic notifications when action is needed.

#### Alert Types

| Alert | When Triggered |
|-------|----------------|
| **Low Stock** | Below minimum level |
| **Out of Stock** | Zero quantity |
| **Expiring Soon** | Within 30/60/90 days |
| **Expired** | Past expiry date |
| **Slow Moving** | No sales in X days |

#### How Alerts Work

- Set minimum stock level for each product
- System monitors continuously
- Alert shown on dashboard
- Optional SMS/email notifications

---

### 5. Stock Adjustments

**What it is:** Handle differences between system and physical stock.

#### Adjustment Reasons

| Reason | When Used |
|--------|-----------|
| **Breakage** | Bottles broken |
| **Theft** | Suspected or confirmed |
| **Damage** | Water damage, label damage |
| **Found Stock** | Discovered extra items |
| **Counting Error** | Physical count differs |

#### Adjustment Process

```
1. Go to Inventory → Adjustments
         │
         ▼
2. Select Product
         │
         ▼
3. Enter Quantity
   - Increase or decrease
         │
         ▼
4. Select Reason
         │
         ▼
5. Add Notes
   - Explain what happened
         │
         ▼
6. Submit for Approval
   (If amount is significant)
```

---

### 6. Purchase Orders

**What it is:** Order stock from your suppliers.

#### Creating Purchase Orders

| Step | Details |
|------|---------|
| **Select Supplier** | From your supplier list |
| **Add Products** | What you need to order |
| **Set Quantities** | How much of each |
| **Review Prices** | Last purchase price shown |
| **Submit Order** | Send to supplier |

#### Order Status Tracking

| Status | Meaning |
|--------|---------|
| **Draft** | Not yet submitted |
| **Submitted** | Sent to supplier |
| **Confirmed** | Supplier accepted |
| **Partially Received** | Some items arrived |
| **Completed** | All items received |
| **Cancelled** | Order cancelled |

---

### 7. Supplier Management

**What it is:** Manage your supplier relationships.

#### Supplier Information

| Field | Purpose |
|-------|---------|
| **Name** | Company name |
| **Contact** | Phone, email |
| **Address** | For orders |
| **Payment Terms** | Credit days |
| **Products** | What they supply |

#### Supplier Features

| Feature | Benefit |
|---------|---------|
| **Purchase History** | See past orders |
| **Price Tracking** | Compare prices over time |
| **Outstanding** | What you owe them |
| **Rating** | Track reliability |

---

### 8. Product Categories

**What it is:** Organize products for easy finding.

#### Default Categories

| Main Category | Sub-Categories |
|---------------|----------------|
| **Whiskey** | Scotch, Indian, Bourbon |
| **Vodka** | Plain, Flavored |
| **Rum** | White, Dark, Spiced |
| **Beer** | Lager, Stout, Craft |
| **Wine** | Red, White, Sparkling |
| **Others** | Mixers, Accessories |

#### Custom Categories

You can create your own:
- Add new categories
- Create sub-categories
- Move products between categories

---

## Inventory Reports

### Available Reports

| Report | What It Shows |
|--------|---------------|
| **Stock Summary** | Current levels for all products |
| **Movement Report** | What came in and went out |
| **Valuation Report** | Total value of inventory |
| **Expiry Report** | Products expiring soon |
| **Low Stock Report** | Products below minimum |
| **Purchase Summary** | Orders and receipts |

---

## Business Benefits

### For Owners

| Benefit | How |
|---------|-----|
| **Reduce Stockouts** | Never miss a sale |
| **Reduce Waste** | Track expiry dates |
| **Better Purchasing** | Know what to order |
| **Loss Prevention** | Track all movements |

### For Staff

| Benefit | How |
|---------|-----|
| **Easy Receiving** | Scan and go |
| **Quick Checks** | Instant stock lookup |
| **Clear Alerts** | Know what needs attention |

---

## Success Metrics

| Metric | Target | Why It Matters |
|--------|--------|---------------|
| **Stock Accuracy** | > 98% | Trust your numbers |
| **Stockout Rate** | < 2% | Never miss sales |
| **Expiry Waste** | < 1% | Minimize losses |
| **Receiving Time** | < 30 min | Efficient operations |

---

## Common Questions

### "How do I do a stock count?"

1. Go to Inventory → Stock Count
2. Select products (all or category)
3. Print count sheet or use mobile
4. Enter physical counts
5. System shows differences
6. Review and approve adjustments

### "What if supplier price changes?"

- Enter new price during receiving
- System tracks price history
- Updated for future calculations
- Old inventory keeps old cost

### "How do I track expiry dates?"

- Enter expiry during receiving
- System alerts before expiry
- Oldest stock sold first (FIFO)
- Block sales of expired items (optional)

### "Can I see what's selling vs. not selling?"

Yes! The "Product Performance" report shows:
- Fast movers - order more
- Slow movers - reduce ordering
- Dead stock - consider discounting

---

## Related Documentation

- [Sales Module](sales-module.md) - Stock updates from sales
- [Finance Module](finance-module.md) - Supplier payments
- [Multi-Shop Module](tenant-module.md) - Stock transfers

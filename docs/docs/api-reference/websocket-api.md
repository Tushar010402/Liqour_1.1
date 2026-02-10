# WebSocket API

## Overview

The WebSocket API provides real-time updates for sales, inventory, and notifications.

**Endpoint**: `wss://new.v2.floelife.in/ws`

---

## Connection

### Authentication

```javascript
const ws = new WebSocket('wss://new.v2.floelife.in/ws?token=<jwt_token>');

ws.onopen = () => {
  console.log('Connected');
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Received:', data);
};

ws.onerror = (error) => {
  console.error('WebSocket error:', error);
};

ws.onclose = () => {
  console.log('Disconnected');
};
```

---

## Event Types

### Sales Events

#### sales.submitted
```json
{
  "event": "sales.submitted",
  "data": {
    "record_id": "uuid",
    "shop_id": "uuid",
    "total_amount": 45000.00,
    "submitted_by": "John Doe"
  },
  "timestamp": "2025-01-11T18:00:00Z"
}
```

#### sales.approved
```json
{
  "event": "sales.approved",
  "data": {
    "record_id": "uuid",
    "shop_id": "uuid",
    "approved_by": "Jane Manager",
    "collection_deadline": "2025-01-11T18:15:00Z"
  },
  "timestamp": "2025-01-11T18:00:00Z"
}
```

#### sales.rejected
```json
{
  "event": "sales.rejected",
  "data": {
    "record_id": "uuid",
    "reason": "Quantity mismatch"
  },
  "timestamp": "2025-01-11T18:00:00Z"
}
```

---

### Inventory Events

#### stock.low
```json
{
  "event": "stock.low",
  "data": {
    "product_id": "uuid",
    "product_name": "Royal Challenge",
    "current_quantity": 5,
    "reorder_level": 20
  },
  "timestamp": "2025-01-11T10:00:00Z"
}
```

---

### Deadline Events

#### deadline.approaching
```json
{
  "event": "deadline.approaching",
  "data": {
    "collection_id": "uuid",
    "amount": 45000.00,
    "time_remaining_seconds": 300
  },
  "timestamp": "2025-01-11T18:10:00Z"
}
```

#### deadline.missed
```json
{
  "event": "deadline.missed",
  "data": {
    "collection_id": "uuid",
    "amount": 45000.00
  },
  "timestamp": "2025-01-11T18:15:00Z"
}
```

---

### Notification Events

#### notification.new
```json
{
  "event": "notification.new",
  "data": {
    "id": "uuid",
    "type": "approval_required",
    "title": "New Approval Request",
    "message": "Daily sales submitted for Main Street Store"
  },
  "timestamp": "2025-01-11T18:00:00Z"
}
```

---

## Heartbeat

Send ping to keep connection alive:

```javascript
setInterval(() => {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'ping' }));
  }
}, 30000);
```

---

## Reconnection

Implement exponential backoff for reconnection:

```javascript
let reconnectDelay = 1000;

function connect() {
  const ws = new WebSocket(url);

  ws.onclose = () => {
    setTimeout(() => {
      reconnectDelay = Math.min(reconnectDelay * 2, 30000);
      connect();
    }, reconnectDelay);
  };

  ws.onopen = () => {
    reconnectDelay = 1000;
  };
}
```

---

## Error Handling

| Error | Description | Action |
|-------|-------------|--------|
| 1000 | Normal close | Reconnect |
| 1001 | Going away | Reconnect |
| 1006 | Abnormal close | Reconnect with backoff |
| 4001 | Unauthorized | Re-authenticate |
| 4002 | Token expired | Refresh token and reconnect |

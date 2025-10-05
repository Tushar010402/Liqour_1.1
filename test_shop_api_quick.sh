#!/bin/bash

echo "============================================"
echo "Shop Management API Quick Test"
echo "============================================"
echo ""

# Step 1: Send OTP
echo "Step 1: Sending OTP..."
OTP_RESP=$(curl -s -X POST http://localhost:8090/api/auth/send-otp \
  -H "Content-Type: application/json" \
  -d '{"mobile":"+919999992020"}')

SESSION_ID=$(echo "$OTP_RESP" | jq -r '.session_id')
echo "✓ Session ID: $SESSION_ID"
echo ""

# Step 2: Verify OTP
echo "Step 2: Verifying OTP (000000)..."
VERIFY_RESP=$(curl -s -X POST http://localhost:8090/api/auth/verify-otp \
  -H "Content-Type: application/json" \
  -d "{\"mobile\":\"+919999992020\",\"otp\":\"000000\",\"session_id\":\"$SESSION_ID\"}")

TOKEN=$(echo "$VERIFY_RESP" | jq -r '.token')
TENANT_ID=$(echo "$VERIFY_RESP" | jq -r '.tenant.id')
echo "✓ Token (first 50 chars): ${TOKEN:0:50}..."
echo "✓ Tenant ID: $TENANT_ID"
echo ""

# Step 3: Get Shops
echo "Step 3: Getting shops list..."
SHOPS_RESP=$(curl -s -X GET http://localhost:8090/api/admin/shops \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Content-Type: application/json")

echo "Response:"
echo "$SHOPS_RESP" | jq '.'
echo ""

# Check if successful
if echo "$SHOPS_RESP" | jq -e 'type == "array"' >/dev/null 2>&1; then
    SHOP_COUNT=$(echo "$SHOPS_RESP" | jq 'length')
    echo "✅ SUCCESS! Got $SHOP_COUNT shop(s)"
    echo ""
    echo "Shop Management API is working 100%!"
else
    echo "❌ FAILED! Response:"
    echo "$SHOPS_RESP"
fi

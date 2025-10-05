#!/bin/bash

# Test with fixed parameters

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TOKEN_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"mobile":"+918630668488","otp":"111111"}' \
    http://localhost:8095/api/saas-admin/verify-otp)
TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

# Extract admin_user_id from token response
ADMIN_USER_ID=$(echo "$TOKEN_RESPONSE" | grep -o '"user_id":"[^"]*' | cut -d'"' -f4)
if [ -z "$ADMIN_USER_ID" ]; then
    ADMIN_USER_ID="admin-123"  # fallback ID
fi

echo "Testing with corrected parameters..."
echo ""

echo "1. Toggle Maintenance Mode (with admin_user_id):"
response=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "X-Admin-User-Id: $ADMIN_USER_ID" \
    -d '{"enabled":false,"admin_user_id":"'$ADMIN_USER_ID'"}' \
    http://localhost:8095/api/super-admin/system/maintenance)
http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')
if [[ "$http_code" =~ ^(200|201)$ ]]; then
    echo -e "${GREEN}✓ Success${NC}"
    echo "$body" | jq '.'
else
    echo -e "${RED}✗ Failed (Status: $http_code)${NC}"
    echo "$body" | jq '.'
fi

echo -e "\n2. Specific Tenant Usage (with resource_type):"
# Add resource_type as query parameter
response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8095/api/super-admin/usage/106e40f8-049b-4661-a5ca-8903ced493c4/current?resource_type=all")
http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')
if [[ "$http_code" =~ ^(200|201)$ ]]; then
    echo -e "${GREEN}✓ Success${NC}"
    echo "$body" | jq '.'
else
    echo -e "${RED}✗ Failed (Status: $http_code)${NC}"
    echo "$body" | jq '.'
fi

echo -e "\n3. Preview Transition (with correct date format):"
response=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "subscription_id":"67271e43-6479-45f6-b174-f1007bd4fe0d",
        "target_plan_id":"df387387-c0d0-4c0a-a462-e85120b51ce0",
        "effective_date":"2025-10-01T00:00:00Z"
    }' \
    http://localhost:8095/api/super-admin/transitions/preview)
http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')
if [[ "$http_code" =~ ^(200|201)$ ]]; then
    echo -e "${GREEN}✓ Success${NC}"
    echo "$body" | jq '.' | head -20
else
    echo -e "${RED}✗ Failed (Status: $http_code)${NC}"
    echo "$body" | jq '.'
fi

echo -e "\n================================"
echo "Testing Complete"
echo "================================"
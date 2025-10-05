#!/bin/bash

# Debug failing endpoints

TOKEN_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"mobile":"+918630668488","otp":"111111"}' \
    http://localhost:8095/api/saas-admin/verify-otp)
TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

echo "Debugging 400 errors..."
echo "Token: ${TOKEN:0:30}..."
echo ""

echo "1. Toggle Maintenance Mode:"
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"enabled":false}' \
    http://localhost:8095/api/super-admin/system/maintenance | jq '.'

echo -e "\n2. Specific Tenant Usage (tenant_id: 106e40f8-049b-4661-a5ca-8903ced493c4):"
curl -s -H "Authorization: Bearer $TOKEN" \
    http://localhost:8095/api/super-admin/usage/106e40f8-049b-4661-a5ca-8903ced493c4/current | jq '.'

echo -e "\n3. Preview Transition:"
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"subscription_id":"67271e43-6479-45f6-b174-f1007bd4fe0d","target_plan_id":"df387387-c0d0-4c0a-a462-e85120b51ce0","effective_date":"2025-10-01"}' \
    http://localhost:8095/api/super-admin/transitions/preview | jq '.'
#!/bin/bash

# Sample script to add inventory data for testing

# You'll need a valid JWT token - get it from the app logs
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NTc5MzE1MDksImlhdCI6MTc1Nzg0NTEwOSwicm9sZSI6ImFkbWluIiwidGVuYW50X2lkIjoiMzczZTk2NWEtNmRlYy00NGQ2LWEyYWItMDQwMDQ0OWZjNzFkIiwidXNlcl9pZCI6ImYzZGIxNTY2LThjNzgtNDdjNy04MWFlLTZkYTRkMTVmNjEzMSJ9.EZp9TA4MTnqVg0AKr8BIrEj4cIbKVBssKoeYH3I70VU"
TENANT_ID="373e965a-6dec-44d6-a2ab-0400449fc71d"
USER_ID="f3db1566-8c78-47c7-81ae-6da4d15f6131"

echo "Creating sample categories..."
curl -X POST http://127.0.0.1:8090/api/inventory/categories \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "X-User-ID: $USER_ID" \
  -d '{"name":"Whisky","description":"Premium whisky products"}' | jq '.'

curl -X POST http://127.0.0.1:8090/api/inventory/categories \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "X-User-ID: $USER_ID" \
  -d '{"name":"Vodka","description":"Premium vodka products"}' | jq '.'

echo "Creating sample brands..."
curl -X POST http://127.0.0.1:8090/api/inventory/brands \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "X-User-ID: $USER_ID" \
  -d '{"name":"Johnnie Walker","description":"Premium Scotch whisky brand"}' | jq '.'

echo "Done! Check the app now to see if real data appears."
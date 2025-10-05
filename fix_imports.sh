#!/bin/bash

echo "🔧 Fixing import paths across the codebase..."

# Find all .go files and replace github.com/liquorpro with github.com/liquorpro/go-backend
find . -name "*.go" -type f -exec sed -i '' 's|github.com/liquorpro/|github.com/liquorpro/go-backend/|g' {} +

# Fix specific import paths that might be malformed
find . -name "*.go" -type f -exec sed -i '' 's|github.com/liquorpro/go-backend/go-backend|github.com/liquorpro/go-backend|g' {} +

echo "✅ Import paths fixed"

echo "🔧 Adding missing dependencies to go.mod..."

# Add missing dependencies
go get github.com/go-redis/redis/v8
go get github.com/golang-jwt/jwt/v4
go get github.com/opentracing/opentracing-go
go get github.com/opentracing/opentracing-go/ext
go get github.com/prometheus/client_golang/prometheus
go get github.com/prometheus/client_golang/prometheus/promauto
go get github.com/prometheus/client_golang/prometheus/promhttp
go get github.com/uber/jaeger-client-go
go get github.com/uber/jaeger-client-go/config
go get github.com/uber/jaeger-client-go/log
go get github.com/uber/jaeger-client-go/metrics

echo "✅ Dependencies added"

echo "🔧 Cleaning up go.mod..."
go mod tidy

echo "✅ Import fix script completed"
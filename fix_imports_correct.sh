#!/bin/bash

echo "🔧 Fixing import paths correctly..."

# First, revert the incorrect changes
find . -name "*.go" -type f -exec sed -i '' 's|github.com/liquorpro/go-backend/github.com/liquorpro/go-backend|github.com/liquorpro/go-backend|g' {} +

# Fix specific paths that should remain as external packages
find . -name "*.go" -type f -exec sed -i '' 's|github.com/liquorpro/go-backend/config|github.com/liquorpro/go-backend/pkg/shared/config|g' {} +

# Now fix all internal import paths to use the correct relative module path
find . -name "*.go" -type f -exec sed -i '' 's|"github.com/liquorpro/internal/|"github.com/liquorpro/go-backend/internal/|g' {} +
find . -name "*.go" -type f -exec sed -i '' 's|"github.com/liquorpro/pkg/|"github.com/liquorpro/go-backend/pkg/|g' {} +
find . -name "*.go" -type f -exec sed -i '' 's|"github.com/liquorpro/cmd/|"github.com/liquorpro/go-backend/cmd/|g' {} +

echo "✅ Import paths fixed correctly"
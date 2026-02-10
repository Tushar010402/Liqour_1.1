#!/bin/bash

# LiquorPro Documentation Deployment Script

set -e

echo "=========================================="
echo "  LiquorPro Documentation Deployment"
echo "=========================================="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if git is initialized
if [ ! -d ".git" ]; then
    echo -e "${YELLOW}Initializing git repository...${NC}"
    git init
    git remote add origin https://github.com/liquorpro/liquorpro-docs.git
fi

# Activate virtual environment
if [ -d "venv" ]; then
    source venv/bin/activate
else
    echo "Running build first..."
    ./build.sh
    source venv/bin/activate
fi

# Deploy to GitHub Pages
echo -e "${BLUE}Deploying to GitHub Pages...${NC}"
mkdocs gh-deploy --force

echo ""
echo -e "${GREEN}=========================================="
echo "  Deployment complete!"
echo "==========================================${NC}"
echo ""
echo "Your documentation is live at:"
echo "  https://liquorpro.github.io/liquorpro-docs/"
echo ""

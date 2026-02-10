#!/bin/bash

# LiquorPro Documentation Build Script

set -e

echo "=========================================="
echo "  LiquorPro Documentation Builder"
echo "=========================================="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "Python3 is required. Please install it first."
    exit 1
fi

# Create virtual environment if not exists
if [ ! -d "venv" ]; then
    echo -e "${BLUE}Creating virtual environment...${NC}"
    python3 -m venv venv
fi

# Activate virtual environment
echo -e "${BLUE}Activating virtual environment...${NC}"
source venv/bin/activate

# Install dependencies
echo -e "${BLUE}Installing dependencies...${NC}"
pip install -q -r requirements.txt

# Build documentation
echo -e "${BLUE}Building documentation...${NC}"
mkdocs build

echo ""
echo -e "${GREEN}=========================================="
echo "  Documentation built successfully!"
echo "  Static files are in: ./site/"
echo "==========================================${NC}"
echo ""
echo "To serve locally:"
echo "  mkdocs serve"
echo ""
echo "To deploy to GitHub Pages:"
echo "  mkdocs gh-deploy"
echo ""

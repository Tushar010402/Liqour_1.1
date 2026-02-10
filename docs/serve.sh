#!/bin/bash

# LiquorPro Documentation Server Script

set -e

echo "=========================================="
echo "  LiquorPro Documentation Server"
echo "=========================================="

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "Virtual environment not found. Running build first..."
    ./build.sh
fi

# Activate virtual environment
source venv/bin/activate

# Serve documentation
echo "Starting documentation server..."
echo "Access at: http://localhost:8000"
echo ""
echo "Press Ctrl+C to stop"
echo ""

mkdocs serve --dev-addr=0.0.0.0:8000

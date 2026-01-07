#!/bin/bash
# Ollama Model Initialization Script for LiquorPro OCR
# This script initializes and pulls the required vision model

set -e

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
MODEL="${OLLAMA_MODEL:-qwen2.5-vl:3b}"

echo "============================================"
echo "LiquorPro Ollama Model Initialization"
echo "============================================"
echo "Ollama Host: $OLLAMA_HOST"
echo "Model: $MODEL"
echo ""

# Wait for Ollama to be ready
echo "Waiting for Ollama service to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1; then
        echo "Ollama is ready!"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "ERROR: Ollama service not available after $MAX_RETRIES retries"
    exit 1
fi

# Check if model is already pulled
echo ""
echo "Checking for existing model..."
EXISTING=$(curl -s "${OLLAMA_HOST}/api/tags" | grep -o "\"name\":\"${MODEL}\"" || true)

if [ -n "$EXISTING" ]; then
    echo "Model '$MODEL' is already installed!"
else
    echo "Pulling model '$MODEL'..."
    echo "This may take 10-20 minutes on first run (downloading ~3GB)..."
    echo ""

    # Pull the model
    curl -X POST "${OLLAMA_HOST}/api/pull" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${MODEL}\"}" \
        --no-buffer

    echo ""
    echo "Model pull complete!"
fi

# Verify model is available
echo ""
echo "Verifying model installation..."
MODELS=$(curl -s "${OLLAMA_HOST}/api/tags")
echo "Available models:"
echo "$MODELS" | grep -o '"name":"[^"]*"' | sed 's/"name":"//g' | sed 's/"//g' | while read -r m; do
    echo "  - $m"
done

# Test the model with a simple prompt
echo ""
echo "Testing model with a simple prompt..."
TEST_RESPONSE=$(curl -s -X POST "${OLLAMA_HOST}/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"${MODEL}\", \"prompt\": \"Say hello\", \"stream\": false}" \
    --max-time 120 || echo "TIMEOUT")

if echo "$TEST_RESPONSE" | grep -q "response"; then
    echo "Model test successful!"
    echo "Response: $(echo "$TEST_RESPONSE" | grep -o '"response":"[^"]*"' | head -1)"
else
    echo "WARNING: Model test may have issues. Response: $TEST_RESPONSE"
fi

echo ""
echo "============================================"
echo "Ollama initialization complete!"
echo "============================================"
echo ""
echo "To test vision capabilities manually, run:"
echo "  curl -X POST ${OLLAMA_HOST}/api/generate \\"
echo "    -d '{\"model\": \"${MODEL}\", \"prompt\": \"Describe this image\", \"images\": [\"<base64_image>\"]}'"

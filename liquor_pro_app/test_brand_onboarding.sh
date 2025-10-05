#!/bin/bash

# Test Brand Onboarding Functionality
# This script runs the Flutter app and monitors for brand onboarding logs

echo "🧪 Starting Brand Onboarding Test..."
echo ""

# Kill any existing Flutter processes
pkill -f "flutter run" 2>/dev/null

# Wait a bit
sleep 2

# Start the app in background
echo "📱 Launching Flutter app on iPhone 16..."
flutter run -d "iPhone 16" > /tmp/brand_onboarding_test.log 2>&1 &
FLUTTER_PID=$!

echo "✅ App launched (PID: $FLUTTER_PID)"
echo "📋 Waiting 30 seconds for app to initialize..."
sleep 30

echo ""
echo "📊 Checking for AuthService initialization..."
grep -i "authservice\|tenant" /tmp/brand_onboarding_test.log | tail -10

echo ""
echo "📊 Checking for Brand Onboarding Service initialization..."
grep -i "brandonboarding\|available brands" /tmp/brand_onboarding_test.log | tail -10

echo ""
echo "⚠️  Checking for errors..."
grep -E "❌|Error|Exception" /tmp/brand_onboarding_test.log | tail -10

echo ""
echo "✅ Checking for successes..."
grep -E "✅|success" /tmp/brand_onboarding_test.log | tail -10

echo ""
echo "📝 Full log available at: /tmp/brand_onboarding_test.log"
echo ""
echo "🔍 To monitor live, run:"
echo "   tail -f /tmp/brand_onboarding_test.log"
echo ""
echo "🛑 To stop the app, run:"
echo "   kill $FLUTTER_PID"
echo ""
echo "💡 Manual Test Instructions:"
echo "   1. Open the app on simulator"
echo "   2. Login with test credentials"
echo "   3. Navigate to Inventory"
echo "   4. Click 'Add from Catalog' button"
echo "   5. Select some brand variants"
echo "   6. Click 'Onboard' button"
echo "   7. Check the logs for success/error messages"
echo ""

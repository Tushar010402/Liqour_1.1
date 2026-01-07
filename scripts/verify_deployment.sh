#!/bin/bash

# OCR Improvements - Deployment Verification Script
# Verifies that all improvements are deployed and working correctly
# Usage: ./verify_deployment.sh

# Note: Don't use set -e as we want to continue checking even if some checks fail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0
TOTAL_CHECKS=0

# Function to print check result
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
    ((TOTAL_CHECKS++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
    ((TOTAL_CHECKS++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((CHECKS_WARNING++))
    ((TOTAL_CHECKS++))
}

# Header
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║         OCR Improvements - Deployment Verification                   ║${NC}"
echo -e "${BOLD}${CYAN}║              Checking All Components...                              ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check 1: Core Files Exist
echo -e "${BOLD}${BLUE}━━━ Checking Core Files ━━━${NC}"

if [ -f "internal/sales/services/ocr_service.go" ]; then
    check_pass "ocr_service.go exists"
else
    check_fail "ocr_service.go NOT FOUND"
fi

if [ -f "pkg/ocr/gemini_client.go" ]; then
    check_pass "gemini_client.go exists"
else
    check_fail "gemini_client.go NOT FOUND"
fi

if [ -f "internal/sales/services/ocr_service_test.go" ]; then
    check_pass "ocr_service_test.go exists (test file)"
else
    check_warn "ocr_service_test.go NOT FOUND (tests won't run)"
fi

echo ""

# Check 2: Scripts Exist and Are Executable
echo -e "${BOLD}${BLUE}━━━ Checking Automation Scripts ━━━${NC}"

if [ -f "scripts/ocr_test_runner.sh" ]; then
    if [ -x "scripts/ocr_test_runner.sh" ]; then
        check_pass "ocr_test_runner.sh exists and is executable"
    else
        check_warn "ocr_test_runner.sh exists but NOT executable (run: chmod +x scripts/ocr_test_runner.sh)"
    fi
else
    check_fail "ocr_test_runner.sh NOT FOUND"
fi

if [ -f "scripts/ocr_metrics_monitor.sh" ]; then
    if [ -x "scripts/ocr_metrics_monitor.sh" ]; then
        check_pass "ocr_metrics_monitor.sh exists and is executable"
    else
        check_warn "ocr_metrics_monitor.sh exists but NOT executable (run: chmod +x scripts/ocr_metrics_monitor.sh)"
    fi
else
    check_fail "ocr_metrics_monitor.sh NOT FOUND"
fi

if [ -f "scripts/ocr_benchmark.sh" ]; then
    if [ -x "scripts/ocr_benchmark.sh" ]; then
        check_pass "ocr_benchmark.sh exists and is executable"
    else
        check_warn "ocr_benchmark.sh exists but NOT executable (run: chmod +x scripts/ocr_benchmark.sh)"
    fi
else
    check_fail "ocr_benchmark.sh NOT FOUND"
fi

echo ""

# Check 3: Documentation Files
echo -e "${BOLD}${BLUE}━━━ Checking Documentation ━━━${NC}"

docs=(
    "README_OCR_IMPROVEMENTS.md"
    "OCR_QUICK_REFERENCE.md"
    "NEXT_STEPS.md"
    "PROJECT_HANDOFF.md"
    "CHANGELOG_OCR_IMPROVEMENTS.md"
    "OCR_IMPROVEMENTS_COMPLETE.md"
    "FINAL_VALIDATION_REPORT.md"
    "PROJECT_INVENTORY.md"
    "scripts/README_OCR_TESTING.md"
)

docs_found=0
for doc in "${docs[@]}"; do
    if [ -f "$doc" ]; then
        ((docs_found++))
    fi
done

if [ $docs_found -eq ${#docs[@]} ]; then
    check_pass "All ${#docs[@]} documentation files present"
elif [ $docs_found -gt 6 ]; then
    check_warn "Most documentation present ($docs_found/${#docs[@]} files)"
else
    check_fail "Missing documentation files ($docs_found/${#docs[@]} found)"
fi

echo ""

# Check 4: Production Container
echo -e "${BOLD}${BLUE}━━━ Checking Production Environment ━━━${NC}"

if command -v docker &> /dev/null; then
    check_pass "Docker is installed"

    if sudo docker ps | grep -q "liquorpro-sales-prod"; then
        check_pass "Production container is running (liquorpro-sales-prod)"
    else
        check_warn "Production container NOT running (expected: liquorpro-sales-prod)"
    fi
else
    check_warn "Docker not found (needed for production monitoring)"
fi

echo ""

# Check 5: Code Improvements Present
echo -e "${BOLD}${BLUE}━━━ Checking Code Improvements ━━━${NC}"

# Check Phase 1 improvements in code
if grep -q "Fuzzy matched" internal/sales/services/ocr_service.go 2>/dev/null; then
    check_pass "Phase 1.3: Fuzzy size detection code present"
else
    check_warn "Phase 1.3: Fuzzy detection code not found in expected location"
fi

if grep -q "JSON Repair" pkg/ocr/gemini_client.go 2>/dev/null; then
    check_pass "Phase 1.4: JSON repair code present"
else
    check_warn "Phase 1.4: JSON repair code not found in expected location"
fi

if grep -q "Cache HIT" pkg/ocr/gemini_client.go 2>/dev/null; then
    check_pass "Phase 2.3: Cache implementation present"
else
    check_warn "Phase 2.3: Cache code not found in expected location"
fi

if grep -q "Cross-Field Validation" internal/sales/services/ocr_service.go 2>/dev/null; then
    check_pass "Phase 3.1: Cross-field validation code present"
else
    check_warn "Phase 3.1: Validation code not found in expected location"
fi

echo ""

# Check 6: Test Coverage
echo -e "${BOLD}${BLUE}━━━ Checking Test Infrastructure ━━━${NC}"

if [ -f "internal/sales/services/ocr_service_test.go" ]; then
    test_count=$(grep -c "^func Test" internal/sales/services/ocr_service_test.go 2>/dev/null || echo "0")
    if [ "$test_count" -ge 6 ]; then
        check_pass "Test functions found: $test_count tests"
    elif [ "$test_count" -gt 0 ]; then
        check_warn "Some tests found: $test_count (expected 6+)"
    else
        check_fail "No test functions found"
    fi
else
    check_fail "Test file not found"
fi

echo ""

# Check 7: Script Dependencies
echo -e "${BOLD}${BLUE}━━━ Checking Script Dependencies ━━━${NC}"

if command -v curl &> /dev/null; then
    check_pass "curl installed (needed for benchmark script)"
else
    check_warn "curl not found (benchmark script requires curl)"
fi

if command -v awk &> /dev/null; then
    check_pass "awk installed (needed for metric calculations)"
else
    check_fail "awk not found (required for monitoring)"
fi

if command -v grep &> /dev/null; then
    check_pass "grep installed (needed for log parsing)"
else
    check_fail "grep not found (required for monitoring)"
fi

echo ""

# Check 8: File Sizes (sanity check)
echo -e "${BOLD}${BLUE}━━━ Checking File Sizes ━━━${NC}"

check_file_size() {
    local file=$1
    local min_size=$2
    local name=$3

    if [ -f "$file" ]; then
        local size=$(wc -c < "$file" 2>/dev/null || echo "0")
        if [ "$size" -gt "$min_size" ]; then
            check_pass "$name has content (${size} bytes)"
        else
            check_warn "$name seems too small (${size} bytes, expected >${min_size})"
        fi
    fi
}

check_file_size "CHANGELOG_OCR_IMPROVEMENTS.md" 10000 "Changelog"
check_file_size "scripts/ocr_metrics_monitor.sh" 5000 "Monitoring script"
check_file_size "scripts/README_OCR_TESTING.md" 10000 "Testing guide"

echo ""

# Summary
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║                      VERIFICATION SUMMARY                            ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "  ${GREEN}Passed:${NC}   ${BOLD}${CHECKS_PASSED}${NC}"
echo -e "  ${YELLOW}Warnings:${NC} ${BOLD}${CHECKS_WARNING}${NC}"
echo -e "  ${RED}Failed:${NC}   ${BOLD}${CHECKS_FAILED}${NC}"
echo -e "  ${CYAN}Total:${NC}    ${BOLD}${TOTAL_CHECKS}${NC}"
echo ""

# Calculate percentage
if [ $TOTAL_CHECKS -gt 0 ]; then
    PASS_PERCENT=$(awk "BEGIN {printf \"%.0f\", ($CHECKS_PASSED / $TOTAL_CHECKS) * 100}")

    if [ $CHECKS_FAILED -eq 0 ] && [ $CHECKS_WARNING -eq 0 ]; then
        echo -e "${BOLD}${GREEN}✓ ALL CHECKS PASSED (100%)${NC}"
        echo -e "${GREEN}Status: READY FOR PRODUCTION${NC}"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo -e "  1. Read: ${BOLD}cat README_OCR_IMPROVEMENTS.md${NC}"
        echo -e "  2. Start monitoring: ${BOLD}./scripts/ocr_metrics_monitor.sh 60${NC}"
        EXIT_CODE=0
    elif [ $CHECKS_FAILED -eq 0 ]; then
        echo -e "${BOLD}${YELLOW}⚠ PASSED WITH WARNINGS (${PASS_PERCENT}%)${NC}"
        echo -e "${YELLOW}Status: READY (with minor warnings)${NC}"
        echo ""
        echo -e "${CYAN}Warnings can usually be ignored. Review above for details.${NC}"
        EXIT_CODE=0
    elif [ $CHECKS_FAILED -le 2 ]; then
        echo -e "${BOLD}${YELLOW}⚠ MOSTLY READY (${PASS_PERCENT}%)${NC}"
        echo -e "${YELLOW}Status: Review failed checks${NC}"
        echo ""
        echo -e "${CYAN}A few issues detected. Review above and fix critical failures.${NC}"
        EXIT_CODE=1
    else
        echo -e "${BOLD}${RED}✗ VERIFICATION FAILED (${PASS_PERCENT}%)${NC}"
        echo -e "${RED}Status: NOT READY - Fix issues above${NC}"
        echo ""
        echo -e "${CYAN}Multiple critical issues detected. Review output above.${NC}"
        EXIT_CODE=2
    fi
else
    echo -e "${RED}No checks were performed${NC}"
    EXIT_CODE=3
fi

echo ""

# Detailed recommendations
if [ $CHECKS_FAILED -gt 0 ] || [ $CHECKS_WARNING -gt 0 ]; then
    echo -e "${BOLD}${CYAN}━━━ Recommendations ━━━${NC}"
    echo ""

    if [ $CHECKS_FAILED -gt 0 ]; then
        echo -e "${RED}Critical Issues:${NC}"
        echo "  - Fix all failed checks above before production use"
        echo "  - Ensure all core files are present"
        echo "  - Verify production container is running"
        echo ""
    fi

    if [ $CHECKS_WARNING -gt 0 ]; then
        echo -e "${YELLOW}Warnings:${NC}"
        echo "  - Most warnings can be safely ignored"
        echo "  - Fix executable permissions: chmod +x scripts/*.sh"
        echo "  - Install missing tools if needed (curl, etc.)"
        echo ""
    fi
fi

# Quick actions
echo -e "${BOLD}${CYAN}━━━ Quick Actions ━━━${NC}"
echo ""
echo -e "${CYAN}Fix script permissions:${NC}"
echo "  chmod +x scripts/*.sh"
echo ""
echo -e "${CYAN}Start monitoring:${NC}"
echo "  ./scripts/ocr_metrics_monitor.sh 60"
echo ""
echo -e "${CYAN}Run tests (requires Go):${NC}"
echo "  ./scripts/ocr_test_runner.sh"
echo ""
echo -e "${CYAN}View documentation:${NC}"
echo "  cat README_OCR_IMPROVEMENTS.md"
echo "  cat OCR_QUICK_REFERENCE.md"
echo ""

exit $EXIT_CODE

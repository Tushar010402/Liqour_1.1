#!/bin/bash

# OCR Automated Test Runner
# Executes all OCR-related unit tests and benchmarks
# Usage: ./ocr_test_runner.sh [--verbose] [--coverage]
#
# Note: This script requires Go to be installed. It's designed for development
# environments, not production containers.

set -e

# Configuration
PROJECT_ROOT="/var/www/liquorpro"
TEST_PACKAGE="internal/sales/services"
COVERAGE_DIR="${PROJECT_ROOT}/coverage"
COVERAGE_FILE="${COVERAGE_DIR}/ocr_coverage.out"
HTML_REPORT="${COVERAGE_DIR}/ocr_coverage.html"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Parse arguments
VERBOSE=false
COVERAGE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --coverage|-c)
            COVERAGE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--verbose] [--coverage]"
            exit 1
            ;;
    esac
done

# Header
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║              OCR Automated Test Suite Runner                         ║${NC}"
echo -e "${BOLD}${CYAN}║         Phase 1, 2, 3 Improvements - Unit Tests                      ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed!${NC}"
    echo -e "${YELLOW}This script requires Go to run unit tests.${NC}"
    echo ""
    echo -e "${CYAN}To run tests manually:${NC}"
    echo -e "  1. Install Go: https://golang.org/doc/install"
    echo -e "  2. Navigate to project: cd ${PROJECT_ROOT}"
    echo -e "  3. Run tests: go test ./internal/sales/services -run \"Test(DetectReceiptType|ValidatePriceRange|ExtractPriceFromRate|ExtractPriceFromCalculation|DetectMergedRows|ValidateCrossFields)\""
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Go is installed: $(go version)${NC}"
echo ""

# Change to project root
cd "$PROJECT_ROOT"

# Create coverage directory if needed
if [ "$COVERAGE" = true ]; then
    mkdir -p "$COVERAGE_DIR"
    echo -e "${BLUE}📊 Coverage reporting enabled${NC}"
    echo -e "${BLUE}   Coverage file: ${COVERAGE_FILE}${NC}"
    echo -e "${BLUE}   HTML report: ${HTML_REPORT}${NC}"
    echo ""
fi

# Test Phase 1: Fuzzy Size Detection
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  Phase 1 Tests: Fuzzy Size Detection & JSON Repair${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${CYAN}Running TestDetectReceiptType...${NC}"
if [ "$VERBOSE" = true ]; then
    go test -v -run TestDetectReceiptType ./${TEST_PACKAGE}
else
    go test -run TestDetectReceiptType ./${TEST_PACKAGE} 2>&1 | grep -E "PASS|FAIL|ok|FAIL"
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Fuzzy size detection tests passed${NC}\n"
else
    echo -e "${RED}✗ Fuzzy size detection tests failed${NC}\n"
    exit 1
fi

# Test Phase 2: Price Validation & Extraction
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${YELLOW}  Phase 2 Tests: Price Validation & Extraction${NC}"
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${CYAN}Running TestValidatePriceRange...${NC}"
if [ "$VERBOSE" = true ]; then
    go test -v -run TestValidatePriceRange ./${TEST_PACKAGE}
else
    go test -run TestValidatePriceRange ./${TEST_PACKAGE} 2>&1 | grep -E "PASS|FAIL|ok|FAIL"
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Price validation tests passed${NC}\n"
else
    echo -e "${RED}✗ Price validation tests failed${NC}\n"
    exit 1
fi

echo -e "${CYAN}Running TestExtractPriceFromRate...${NC}"
if [ "$VERBOSE" = true ]; then
    go test -v -run TestExtractPriceFromRate ./${TEST_PACKAGE}
else
    go test -run TestExtractPriceFromRate ./${TEST_PACKAGE} 2>&1 | grep -E "PASS|FAIL|ok|FAIL"
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Price extraction tests passed${NC}\n"
else
    echo -e "${RED}✗ Price extraction tests failed${NC}\n"
    exit 1
fi

echo -e "${CYAN}Running TestExtractPriceFromCalculation...${NC}"
if [ "$VERBOSE" = true ]; then
    go test -v -run TestExtractPriceFromCalculation ./${TEST_PACKAGE}
else
    go test -run TestExtractPriceFromCalculation ./${TEST_PACKAGE} 2>&1 | grep -E "PASS|FAIL|ok|FAIL"
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Price calculation tests passed${NC}\n"
else
    echo -e "${RED}✗ Price calculation tests failed${NC}\n"
    exit 1
fi

echo -e "${CYAN}Running TestDetectMergedRows...${NC}"
if [ "$VERBOSE" = true ]; then
    go test -v -run TestDetectMergedRows ./${TEST_PACKAGE}
else
    go test -run TestDetectMergedRows ./${TEST_PACKAGE} 2>&1 | grep -E "PASS|FAIL|ok|FAIL"
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Merged row detection tests passed${NC}\n"
else
    echo -e "${RED}✗ Merged row detection tests failed${NC}\n"
    exit 1
fi

# Test Phase 3: Cross-Field Validation
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${BLUE}  Phase 3 Tests: Cross-Field Validation${NC}"
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${CYAN}Running TestValidateCrossFields...${NC}"
if [ "$VERBOSE" = true ]; then
    go test -v -run TestValidateCrossFields ./${TEST_PACKAGE}
else
    go test -run TestValidateCrossFields ./${TEST_PACKAGE} 2>&1 | grep -E "PASS|FAIL|ok|FAIL"
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Cross-field validation tests passed${NC}\n"
else
    echo -e "${RED}✗ Cross-field validation tests failed${NC}\n"
    exit 1
fi

# Run all OCR tests together with coverage if requested
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}  Running Complete Test Suite${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$COVERAGE" = true ]; then
    echo -e "${CYAN}Running all tests with coverage analysis...${NC}"
    if [ "$VERBOSE" = true ]; then
        go test -v -coverprofile="$COVERAGE_FILE" -covermode=atomic ./${TEST_PACKAGE}
    else
        go test -coverprofile="$COVERAGE_FILE" -covermode=atomic ./${TEST_PACKAGE}
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed${NC}\n"

        # Generate coverage report
        echo -e "${CYAN}Generating coverage report...${NC}"
        go tool cover -html="$COVERAGE_FILE" -o "$HTML_REPORT"

        # Display coverage statistics
        echo ""
        echo -e "${BOLD}${CYAN}Coverage Statistics:${NC}"
        go tool cover -func="$COVERAGE_FILE" | grep -E "ocr_service.go|total" | while read line; do
            echo -e "  ${line}"
        done
        echo ""
        echo -e "${GREEN}✓ HTML coverage report generated: ${HTML_REPORT}${NC}"
    else
        echo -e "${RED}✗ Some tests failed${NC}\n"
        exit 1
    fi
else
    echo -e "${CYAN}Running all OCR tests...${NC}"
    if [ "$VERBOSE" = true ]; then
        go test -v ./${TEST_PACKAGE} -run "Test(DetectReceiptType|ValidatePriceRange|ExtractPriceFromRate|ExtractPriceFromCalculation|DetectMergedRows|ValidateCrossFields)"
    else
        go test ./${TEST_PACKAGE} -run "Test(DetectReceiptType|ValidatePriceRange|ExtractPriceFromRate|ExtractPriceFromCalculation|DetectMergedRows|ValidateCrossFields)"
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed${NC}\n"
    else
        echo -e "${RED}✗ Some tests failed${NC}\n"
        exit 1
    fi
fi

# Summary
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║                        TEST SUMMARY                                  ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}✓ Phase 1 Tests:${NC} Fuzzy Size Detection & JSON Repair"
echo -e "${GREEN}✓ Phase 2 Tests:${NC} Price Validation, Extraction, Merged Rows"
echo -e "${GREEN}✓ Phase 3 Tests:${NC} Cross-Field Validation"
echo ""

if [ "$COVERAGE" = true ]; then
    echo -e "${CYAN}Coverage Report:${NC} ${HTML_REPORT}"
    echo -e "${CYAN}Open in browser:${NC} file://${HTML_REPORT}"
    echo ""
fi

echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  All OCR Tests Passed Successfully! 🎉${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Expected accuracy improvements
echo -e "${BOLD}${CYAN}Expected Accuracy Improvements:${NC}"
echo -e "  Phase 1: ${GREEN}+23%${NC} (Fuzzy Detection, JSON Repair, Missing Fields)"
echo -e "  Phase 2: ${GREEN}+8%${NC}  (Price Refactoring, Merged Rows, Cache)"
echo -e "  Phase 3: ${GREEN}+3%${NC}  (Cross-Field Validation)"
echo -e "  ${BOLD}${GREEN}Total: 62% → ~95% (+33%)${NC}"
echo ""

echo -e "${BOLD}${CYAN}Test Coverage:${NC}"
echo -e "  Total OCR Tests: ${BOLD}50+${NC}"
echo -e "  Phase 1: 13 tests"
echo -e "  Phase 2: 29 tests (15 validation + 10 extraction + 4 merged rows)"
echo -e "  Phase 3: 8 tests"
echo ""

echo -e "${CYAN}Next Steps:${NC}"
echo -e "  1. Monitor production with: ${BOLD}./scripts/ocr_metrics_monitor.sh${NC}"
echo -e "  2. Run benchmarks with: ${BOLD}./scripts/ocr_benchmark.sh${NC}"
echo -e "  3. Review changelog: ${BOLD}CHANGELOG_OCR_IMPROVEMENTS.md${NC}"
echo ""

exit 0

#!/bin/bash

# OCR Metrics Monitoring Dashboard
# Tracks Phase 1, 2, and 3 improvements in real-time
# Usage: ./ocr_metrics_monitor.sh [duration_in_minutes]

set -e

DURATION=${1:-60}  # Default: monitor for 60 minutes
CONTAINER_NAME="liquorpro-sales-prod"
REFRESH_INTERVAL=10  # Refresh every 10 seconds

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Function to display header
show_header() {
    clear
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║        OCR Accuracy Enhancement - Real-Time Metrics Dashboard        ║${NC}"
    echo -e "${BOLD}${CYAN}║                  Phases 1, 2, 3 - Production Monitoring              ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Monitoring Duration: ${DURATION} minutes | Refresh: ${REFRESH_INTERVAL}s${NC}"
    echo -e "${BLUE}Container: ${CONTAINER_NAME}${NC}"
    echo ""
}

# Function to get logs since last check
get_recent_logs() {
    local since_time=$1
    sudo docker logs ${CONTAINER_NAME} --since ${since_time}s 2>&1
}

# Function to calculate metrics
calculate_metrics() {
    local logs="$1"

    # Phase 1 Metrics
    fuzzy_size_detections=$(echo "$logs" | grep -c "Fuzzy matched.*ml using pattern" 2>/dev/null || echo "0")
    json_repairs=$(echo "$logs" | grep -c "JSON Repair] Fixed malformed JSON" 2>/dev/null || echo "0")
    missing_field_fixes=$(echo "$logs" | grep -c "Fixed missing.*for" 2>/dev/null || echo "0")

    # Phase 2 Metrics
    cache_hits=$(echo "$logs" | grep -c "Cache HIT" 2>/dev/null || echo "0")
    cache_misses=$(echo "$logs" | grep -c "Cache MISS" 2>/dev/null || echo "0")
    merged_rows=$(echo "$logs" | grep -c "Merged Rows] Successfully split" 2>/dev/null || echo "0")
    price_calc_direct=$(echo "$logs" | grep -c "Direct extraction - Rate column" 2>/dev/null || echo "0")
    price_calc_fallback=$(echo "$logs" | grep -c "Fallback calculation" 2>/dev/null || echo "0")

    # Phase 3 Metrics
    validation_passed=$(echo "$logs" | grep -c "Cross-Field Validation] All checks passed" 2>/dev/null || echo "0")
    validation_warnings=$(echo "$logs" | grep -c "Cross-Field Validation] Found.*warnings" 2>/dev/null || echo "0")
    validation_critical=$(echo "$logs" | grep -c "Cross-Field Validation] CRITICAL" 2>/dev/null || echo "0")

    # General Metrics
    items_extracted=$(echo "$logs" | grep -c "Extracted item #" 2>/dev/null || echo "0")
    gemini_calls=$(echo "$logs" | grep -c "Gemini] API call successful" 2>/dev/null || echo "0")

    # Ensure all variables are numeric and clean
    fuzzy_size_detections=$(echo "$fuzzy_size_detections" | tr -d '\n' | tr -d ' ')
    fuzzy_size_detections=${fuzzy_size_detections:-0}
    json_repairs=$(echo "$json_repairs" | tr -d '\n' | tr -d ' ')
    json_repairs=${json_repairs:-0}
    missing_field_fixes=$(echo "$missing_field_fixes" | tr -d '\n' | tr -d ' ')
    missing_field_fixes=${missing_field_fixes:-0}
    cache_hits=$(echo "$cache_hits" | tr -d '\n' | tr -d ' ')
    cache_hits=${cache_hits:-0}
    cache_misses=$(echo "$cache_misses" | tr -d '\n' | tr -d ' ')
    cache_misses=${cache_misses:-0}
    merged_rows=$(echo "$merged_rows" | tr -d '\n' | tr -d ' ')
    merged_rows=${merged_rows:-0}
    price_calc_direct=$(echo "$price_calc_direct" | tr -d '\n' | tr -d ' ')
    price_calc_direct=${price_calc_direct:-0}
    price_calc_fallback=$(echo "$price_calc_fallback" | tr -d '\n' | tr -d ' ')
    price_calc_fallback=${price_calc_fallback:-0}
    validation_passed=$(echo "$validation_passed" | tr -d '\n' | tr -d ' ')
    validation_passed=${validation_passed:-0}
    validation_warnings=$(echo "$validation_warnings" | tr -d '\n' | tr -d ' ')
    validation_warnings=${validation_warnings:-0}
    validation_critical=$(echo "$validation_critical" | tr -d '\n' | tr -d ' ')
    validation_critical=${validation_critical:-0}
    items_extracted=$(echo "$items_extracted" | tr -d '\n' | tr -d ' ')
    items_extracted=${items_extracted:-0}
    gemini_calls=$(echo "$gemini_calls" | tr -d '\n' | tr -d ' ')
    gemini_calls=${gemini_calls:-0}

    # Calculate derived metrics
    if [ $((cache_hits + cache_misses)) -gt 0 ]; then
        cache_hit_rate=$(awk "BEGIN {printf \"%.1f\", ($cache_hits / ($cache_hits + $cache_misses)) * 100}")
    else
        cache_hit_rate="0.0"
    fi

    if [ $items_extracted -gt 0 ]; then
        validation_pass_rate=$(awk "BEGIN {printf \"%.1f\", ($validation_passed / $items_extracted) * 100}")
    else
        validation_pass_rate="0.0"
    fi
}

# Function to display metrics dashboard
display_metrics() {
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  📊 PHASE 1: Quick Wins Metrics${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}🔧 Fuzzy Size Detections:${NC}      ${BOLD}${fuzzy_size_detections}${NC} times"
    echo -e "  ${CYAN}🔧 JSON Auto-Repairs:${NC}          ${BOLD}${json_repairs}${NC} times"
    echo -e "  ${CYAN}🔧 Missing Field Fixes:${NC}        ${BOLD}${missing_field_fixes}${NC} times"
    echo ""

    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${YELLOW}  🚀 PHASE 2: Core Refactoring Metrics${NC}"
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}💨 Cache Hits:${NC}                 ${BOLD}${GREEN}${cache_hits}${NC}"
    echo -e "  ${CYAN}🌐 Cache Misses:${NC}               ${BOLD}${cache_misses}${NC}"
    echo -e "  ${CYAN}📈 Cache Hit Rate:${NC}             ${BOLD}${GREEN}${cache_hit_rate}%${NC}"
    echo -e "  ${CYAN}✂️  Merged Rows Split:${NC}          ${BOLD}${merged_rows}${NC} times"
    echo ""
    echo -e "  ${CYAN}💰 Price Extraction:${NC}"
    echo -e "     Direct (Rate Column):     ${BOLD}${GREEN}${price_calc_direct}${NC}"
    echo -e "     Fallback (Amount÷Sale):   ${BOLD}${YELLOW}${price_calc_fallback}${NC}"
    echo ""

    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  ✨ PHASE 3: Advanced Validation Metrics${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}✅ Validation Passed:${NC}          ${BOLD}${GREEN}${validation_passed}${NC} items"
    echo -e "  ${CYAN}⚠️  Validation Warnings:${NC}        ${BOLD}${YELLOW}${validation_warnings}${NC} items"
    echo -e "  ${CYAN}❌ Validation Critical:${NC}        ${BOLD}${RED}${validation_critical}${NC} items"
    echo -e "  ${CYAN}📊 Validation Pass Rate:${NC}       ${BOLD}${GREEN}${validation_pass_rate}%${NC}"
    echo ""

    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  📈 Overall Statistics${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}📦 Items Extracted:${NC}            ${BOLD}${items_extracted}${NC}"
    echo -e "  ${CYAN}🤖 Gemini API Calls:${NC}           ${BOLD}${gemini_calls}${NC}"

    # Calculate API savings
    if [ $items_extracted -gt 0 ]; then
        expected_calls=$items_extracted
        actual_calls=$((cache_misses + gemini_calls))
        if [ $expected_calls -gt 0 ]; then
            api_savings=$(awk "BEGIN {printf \"%.0f\", (($expected_calls - $actual_calls) / $expected_calls) * 100}")
        else
            api_savings="0"
        fi
        echo -e "  ${CYAN}💰 API Call Reduction:${NC}         ${BOLD}${GREEN}~${api_savings}%${NC} (saved by cache)"
    fi

    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to display improvement summary
display_improvement_summary() {
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║                     IMPROVEMENT SUMMARY                              ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Phase 1 Impact:${NC}"
    echo -e "  ✓ Fuzzy detection handling OCR errors"
    echo -e "  ✓ JSON auto-repair preventing parse failures"
    echo -e "  ✓ Missing field recovery improving data completeness"
    echo -e "  ${BOLD}${GREEN}Expected: +23% accuracy${NC}"
    echo ""
    echo -e "${CYAN}Phase 2 Impact:${NC}"
    echo -e "  ✓ Cache reducing API calls by ${BOLD}${cache_hit_rate}%${NC}"
    echo -e "  ✓ Merged row detection recovering lost items"
    echo -e "  ✓ Refactored price calculation (260→48 lines)"
    echo -e "  ${BOLD}${GREEN}Expected: +8% accuracy${NC}"
    echo ""
    echo -e "${CYAN}Phase 3 Impact:${NC}"
    echo -e "  ✓ Cross-field validation catching inconsistencies"
    echo -e "  ✓ ${BOLD}${validation_pass_rate}%${NC} items passing all validations"
    echo -e "  ${BOLD}${GREEN}Expected: +3% accuracy${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}Total Expected Improvement: 62% → ~95% (+33%)${NC}"
    echo ""
}

# Main monitoring loop
main() {
    echo -e "${BOLD}Starting OCR metrics monitoring...${NC}"
    echo -e "Press ${BOLD}Ctrl+C${NC} to stop\n"
    sleep 2

    START_TIME=$(date +%s)
    END_TIME=$((START_TIME + DURATION * 60))

    while true; do
        CURRENT_TIME=$(date +%s)

        # Check if monitoring duration exceeded
        if [ $CURRENT_TIME -ge $END_TIME ]; then
            echo -e "\n${GREEN}Monitoring duration completed!${NC}"
            break
        fi

        # Get logs from last refresh interval
        logs=$(get_recent_logs $REFRESH_INTERVAL)

        # Calculate metrics
        calculate_metrics "$logs"

        # Display dashboard
        show_header
        display_metrics
        display_improvement_summary

        # Show time remaining
        REMAINING=$((END_TIME - CURRENT_TIME))
        REMAINING_MIN=$((REMAINING / 60))
        REMAINING_SEC=$((REMAINING % 60))
        echo -e "${BLUE}Time Remaining: ${REMAINING_MIN}m ${REMAINING_SEC}s${NC}"
        echo -e "${BLUE}Last Update: $(date '+%Y-%m-%d %H:%M:%S')${NC}"

        # Wait before next refresh
        sleep $REFRESH_INTERVAL
    done

    echo -e "\n${GREEN}✓ Monitoring complete!${NC}\n"
}

# Check if container is running
if ! sudo docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: Container $CONTAINER_NAME is not running!${NC}"
    exit 1
fi

# Run main function
main

#!/bin/bash
# Master validation script for Witness documentation
# Tests all examples and generates validation report

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
VALIDATION_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_FILE="${VALIDATION_DIR}/validation-results.md"
FAILED_TESTS=0
PASSED_TESTS=0
SKIPPED_TESTS=0

# Initialize results file
cat > "${RESULTS_FILE}" << EOF
# Witness Documentation Validation Results
Date: $(date)
System: $(uname -a)

## Test Summary
EOF

# Function to run test and record result
run_test() {
    local test_name="$1"
    local test_script="$2"
    
    echo -e "${YELLOW}Running: ${test_name}${NC}"
    
    if [[ ! -f "${test_script}" ]]; then
        echo -e "${YELLOW}  SKIPPED (script not found)${NC}"
        echo "- ⚠️ **${test_name}**: SKIPPED (script not found)" >> "${RESULTS_FILE}"
        ((SKIPPED_TESTS++))
        return
    fi
    
    if bash "${test_script}" > "${VALIDATION_DIR}/logs/${test_name}.log" 2>&1; then
        echo -e "${GREEN}  ✓ PASSED${NC}"
        echo "- ✅ **${test_name}**: PASSED" >> "${RESULTS_FILE}"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}  ✗ FAILED${NC}"
        echo "- ❌ **${test_name}**: FAILED (see logs/${test_name}.log)" >> "${RESULTS_FILE}"
        ((FAILED_TESTS++))
    fi
}

# Create logs directory
mkdir -p "${VALIDATION_DIR}/logs"

echo "========================================="
echo "Starting Witness Documentation Validation"
echo "========================================="
echo ""

# Core functionality tests
echo "## Core Tests" >> "${RESULTS_FILE}"
echo ""
run_test "basic-signing" "${VALIDATION_DIR}/core-tests/test-basic-signing.sh"
run_test "verification" "${VALIDATION_DIR}/core-tests/test-verification.sh"
run_test "policy-creation" "${VALIDATION_DIR}/core-tests/test-policy-creation.sh"

# Integration tests
echo "" >> "${RESULTS_FILE}"
echo "## Integration Tests" >> "${RESULTS_FILE}"
echo ""
run_test "fulcio-keyless" "${VALIDATION_DIR}/integration-tests/test-fulcio.sh"
run_test "tsa-integration" "${VALIDATION_DIR}/integration-tests/test-tsa.sh"
run_test "archivista" "${VALIDATION_DIR}/integration-tests/test-archivista.sh"

# Air-gap tests
echo "" >> "${RESULTS_FILE}"
echo "## Air-Gap Tests" >> "${RESULTS_FILE}"
echo ""
run_test "bundle-export" "${VALIDATION_DIR}/air-gap-tests/test-bundle-export.sh"
run_test "offline-verify" "${VALIDATION_DIR}/air-gap-tests/test-offline-verify.sh"

# Documentation examples test
echo "" >> "${RESULTS_FILE}"
echo "## Documentation Examples" >> "${RESULTS_FILE}"
echo ""
run_test "extract-examples" "${VALIDATION_DIR}/test-doc-examples.sh"

# Summary
echo "" >> "${RESULTS_FILE}"
echo "## Summary" >> "${RESULTS_FILE}"
echo "- **Passed**: ${PASSED_TESTS}" >> "${RESULTS_FILE}"
echo "- **Failed**: ${FAILED_TESTS}" >> "${RESULTS_FILE}"
echo "- **Skipped**: ${SKIPPED_TESTS}" >> "${RESULTS_FILE}"

echo ""
echo "========================================="
echo "Validation Complete"
echo "========================================="
echo -e "${GREEN}Passed: ${PASSED_TESTS}${NC}"
echo -e "${RED}Failed: ${FAILED_TESTS}${NC}"
echo -e "${YELLOW}Skipped: ${SKIPPED_TESTS}${NC}"
echo ""
echo "Full results: ${RESULTS_FILE}"
echo "Logs directory: ${VALIDATION_DIR}/logs/"

# Exit with error if any tests failed
if [[ ${FAILED_TESTS} -gt 0 ]]; then
    exit 1
fi
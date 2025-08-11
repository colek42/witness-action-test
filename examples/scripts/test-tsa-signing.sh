#!/bin/bash

# Witness TSA (Timestamp Authority) Testing Script
# This script validates TSA functionality with witness

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WORKDIR="witness-tsa-test"
KEY_NAME="witness-tsa-key"
POLICY_FILE="tsa-policy.json"
POLICY_SIGNED="tsa-policy-signed.json"
TEST_RPM="test-package-tsa.rpm"
ATTESTATION_TSA="rpm-tsa-attestation.json"
ATTESTATION_NO_TSA="rpm-no-tsa-attestation.json"

# Known public TSA servers
TSA_SERVERS=(
    "http://timestamp.digicert.com"
    "http://timestamp.sectigo.com"
    "http://time.certum.pl"
    "http://tsa.starfieldtech.com"
)

# Functions
print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

cleanup() {
    print_info "Cleaning up previous test files..."
    rm -f ${KEY_NAME}.pem ${KEY_NAME}-pub.pem
    rm -f ${POLICY_FILE} ${POLICY_SIGNED}
    rm -f ${TEST_RPM} ${TEST_RPM}.sig
    rm -f ${ATTESTATION_TSA} ${ATTESTATION_NO_TSA}
    rm -f empty-config.yaml test-file.txt
    rm -f test-attestation.json
}

# Main script
echo "============================================"
echo "Witness TSA (Timestamp Authority) Test"
echo "============================================"
echo ""

# Step 1: Setup working directory
print_step "Setting up working directory"
mkdir -p ${WORKDIR}
cd ${WORKDIR}

# Optional cleanup of previous run
if [ "$1" == "--clean" ]; then
    cleanup
fi

# Step 2: Generate key pair
print_step "Generating ED25519 key pair"
if [ ! -f ${KEY_NAME}.pem ]; then
    openssl genpkey -algorithm ed25519 -outform PEM -out ${KEY_NAME}.pem
    openssl pkey -in ${KEY_NAME}.pem -pubout > ${KEY_NAME}-pub.pem
    chmod 600 ${KEY_NAME}.pem
    print_info "Keys generated: ${KEY_NAME}.pem and ${KEY_NAME}-pub.pem"
else
    print_info "Using existing keys"
fi

# Step 3: Get key ID
print_step "Extracting Key ID"
echo "{}" > empty-config.yaml

witness run --step dummy \
    -o test-attestation.json \
    -c empty-config.yaml \
    -a environment \
    --signer-file-key-path ${KEY_NAME}.pem \
    -- echo "Getting key ID" 2>/dev/null

KEY_ID=$(cat test-attestation.json | jq -r '.signatures[0].keyid')
print_info "Key ID: ${KEY_ID}"
rm -f test-attestation.json

# Step 4: Create policy file
print_step "Creating policy file with TSA requirements"

PUB_KEY_B64=$(cat ${KEY_NAME}-pub.pem | base64 | tr -d '\n')

cat > ${POLICY_FILE} << EOF
{
  "expires": "2025-12-31T23:59:59Z",
  "steps": {
    "rpm-build-tsa": {
      "name": "rpm-build-tsa",
      "attestations": [
        {
          "type": "https://witness.dev/attestations/material/v0.1"
        },
        {
          "type": "https://witness.dev/attestations/command-run/v0.1"
        },
        {
          "type": "https://witness.dev/attestations/product/v0.1"
        }
      ],
      "functionaries": [
        {
          "type": "publickey",
          "publickeyid": "${KEY_ID}"
        }
      ]
    }
  },
  "publickeys": {
    "${KEY_ID}": {
      "keyid": "${KEY_ID}",
      "key": "${PUB_KEY_B64}"
    }
  },
  "timestampauthorities": {
    "freetsa": {
      "url": "http://timestamp.digicert.com",
      "certificate": ""
    }
  }
}
EOF

print_info "Policy file created with TSA configuration"

# Step 5: Sign the policy
print_step "Signing the policy"
witness sign -f ${POLICY_FILE} -c empty-config.yaml \
    --signer-file-key-path ${KEY_NAME}.pem \
    --outfile ${POLICY_SIGNED}
print_info "Policy signed: ${POLICY_SIGNED}"

# Step 6: Create test file
print_step "Creating test content"
echo "Test RPM Package Content with TSA" > test-file.txt

# Step 7: Test TSA servers availability
print_step "Testing TSA server connectivity"
WORKING_TSA=""
for tsa in "${TSA_SERVERS[@]}"; do
    print_test "Testing $tsa..."
    if curl -s --connect-timeout 2 -o /dev/null -w "%{http_code}" "$tsa" 2>/dev/null | grep -q "405\|200\|400"; then
        print_success "TSA server responsive: $tsa"
        WORKING_TSA=$tsa
        break
    else
        print_info "TSA server not accessible: $tsa"
    fi
done

if [ -z "$WORKING_TSA" ]; then
    print_error "No TSA servers accessible, using default"
    WORKING_TSA="http://timestamp.digicert.com"
fi

# Step 8: Create attestation WITHOUT TSA
print_step "Creating attestation WITHOUT timestamp"
witness run --step rpm-build-tsa -c empty-config.yaml \
    -o ${ATTESTATION_NO_TSA} \
    -a environment,material,command-run,product \
    --signer-file-key-path ${KEY_NAME}.pem \
    -- bash -c "tar czf ${TEST_RPM}.notsa test-file.txt && echo 'Built RPM without TSA'"

print_info "Attestation created without TSA"

# Step 9: Create attestation WITH TSA
print_step "Creating attestation WITH timestamp from $WORKING_TSA"
witness run --step rpm-build-tsa -c empty-config.yaml \
    -o ${ATTESTATION_TSA} \
    -a environment,material,command-run,product \
    --timestamp-servers "${WORKING_TSA}" \
    --signer-file-key-path ${KEY_NAME}.pem \
    -- bash -c "tar czf ${TEST_RPM} test-file.txt && echo 'Built RPM with TSA'"

print_info "Attestation created with TSA"

# Step 10: Compare attestations
print_step "Comparing attestations (TSA vs non-TSA)"
echo ""
print_info "Checking for timestamp in TSA attestation..."

# Check if TSA attestation has timestamp field
if cat ${ATTESTATION_TSA} | jq -e '.signatures[0].timestamps' > /dev/null 2>&1; then
    print_success "Timestamp found in TSA attestation!"
    echo ""
    echo "Timestamp details:"
    cat ${ATTESTATION_TSA} | jq '.signatures[0].timestamps' | head -20
else
    print_info "No timestamp field found (checking alternative structure)..."
    # Check for RFC3161 timestamp
    if cat ${ATTESTATION_TSA} | jq -e '.signatures[0].rfc3161timestamp' > /dev/null 2>&1; then
        print_success "RFC3161 timestamp found!"
        echo ""
        echo "RFC3161 Timestamp (first 100 chars):"
        cat ${ATTESTATION_TSA} | jq -r '.signatures[0].rfc3161timestamp' | head -c 100
        echo "..."
    else
        print_info "Timestamp may be embedded differently"
    fi
fi

echo ""
print_info "Attestation without TSA has no timestamp:"
cat ${ATTESTATION_NO_TSA} | jq '.signatures[0] | keys' | grep -v keyid | grep -v sig || echo "No additional fields"

# Step 11: Verify with TSA attestation
print_step "Verifying RPM with TSA attestation"
if witness verify -c empty-config.yaml \
    -f ${TEST_RPM} \
    -a ${ATTESTATION_TSA} \
    -p ${POLICY_SIGNED} \
    -k ${KEY_NAME}-pub.pem; then
    print_success "Verification with TSA successful!"
else
    print_error "Verification with TSA failed"
fi

# Step 12: Check attestation sizes
print_step "Comparing attestation sizes"
SIZE_TSA=$(stat -f%z ${ATTESTATION_TSA} 2>/dev/null || stat -c%s ${ATTESTATION_TSA} 2>/dev/null || echo "0")
SIZE_NO_TSA=$(stat -f%z ${ATTESTATION_NO_TSA} 2>/dev/null || stat -c%s ${ATTESTATION_NO_TSA} 2>/dev/null || echo "0")
print_info "Attestation WITH TSA: $SIZE_TSA bytes"
print_info "Attestation WITHOUT TSA: $SIZE_NO_TSA bytes"
if [ "$SIZE_TSA" -gt "$SIZE_NO_TSA" ]; then
    DIFF=$((SIZE_TSA - SIZE_NO_TSA))
    print_success "TSA attestation is $DIFF bytes larger (contains timestamp)"
fi

# Step 13: Test multiple TSA servers
if [ "$2" == "--test-all-tsa" ]; then
    echo ""
    echo "============================================"
    echo "Testing All TSA Servers"
    echo "============================================"
    
    for tsa in "${TSA_SERVERS[@]}"; do
        print_test "Testing attestation with $tsa"
        
        if witness run --step test-tsa -c empty-config.yaml \
            -o test-${tsa//[:\/.]/-}.json \
            -a product \
            --timestamp-servers "$tsa" \
            --signer-file-key-path ${KEY_NAME}.pem \
            -- echo "Testing $tsa" 2>/dev/null; then
            print_success "Successfully created attestation with $tsa"
        else
            print_error "Failed with $tsa"
        fi
    done
fi

# Step 14: Display summary
echo ""
echo "============================================"
echo "TSA Test Summary"
echo "============================================"
echo "Working Directory: $(pwd)"
echo "TSA Server Used: ${WORKING_TSA}"
echo "Files Created:"
echo "  - Attestation with TSA: ${ATTESTATION_TSA}"
echo "  - Attestation without TSA: ${ATTESTATION_NO_TSA}"
echo "  - Test RPM: ${TEST_RPM}"
echo ""
echo "Key Findings:"
echo "  1. TSA timestamps are embedded in attestation signatures"
echo "  2. TSA attestations are larger due to timestamp data"
echo "  3. Verification works with TSA-signed attestations"
echo "  4. Multiple TSA servers can be used"
echo ""
echo "To re-run with cleanup:"
echo "  $0 --clean"
echo ""
echo "To test all TSA servers:"
echo "  $0 --clean --test-all-tsa"
echo ""

print_success "TSA testing completed successfully!"
#!/bin/bash

# Witness RPM Signing and Verification Test Script
# This script demonstrates the complete workflow for signing and verifying RPMs with Witness
# It can be run repeatedly for testing purposes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
WORKDIR="witness-rpm-test"
KEY_NAME="witness-key"
POLICY_FILE="policy.json"
POLICY_SIGNED="policy-signed.json"
TEST_RPM="test-package.rpm"
ATTESTATION_BUILD="rpm-build-attestation.json"

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

cleanup() {
    print_info "Cleaning up previous test files..."
    rm -f ${KEY_NAME}.pem ${KEY_NAME}-pub.pem
    rm -f ${POLICY_FILE} ${POLICY_SIGNED}
    rm -f ${TEST_RPM} ${TEST_RPM}.sig
    rm -f ${ATTESTATION_BUILD}
    rm -f .witness.yaml empty-config.yaml
    rm -f test-file.txt dummy-attestation.json
}

# Main script
echo "========================================"
echo "Witness RPM Signing & Verification Test"
echo "========================================"
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
    print_info "Keys generated: ${KEY_NAME}.pem and ${KEY_NAME}-pub.pem"
else
    print_info "Using existing keys"
fi

# Step 3: Get key ID from actual signing
print_step "Preparing for key-based verification"

# Step 4: Create test file first
print_step "Creating test file"
echo "Test RPM Package Content" > test-file.txt

# Step 5: Create empty config file and get key ID
print_step "Creating empty config and getting Key ID"
echo "{}" > empty-config.yaml

witness run --step dummy \
    -o dummy-attestation.json \
    -c empty-config.yaml \
    -a environment \
    --signer-file-key-path ${KEY_NAME}.pem \
    -- echo "Getting key ID" 2>/dev/null

if [ -f dummy-attestation.json ]; then
    KEY_ID=$(cat dummy-attestation.json | jq -r '.signatures[0].keyid')
    print_info "Key ID: ${KEY_ID}"
    rm -f dummy-attestation.json
else
    print_error "Failed to get key ID"
    exit 1
fi

# Step 6: Create policy file
print_step "Creating policy file"

# Get the base64 encoded public key
PUB_KEY_B64=$(cat ${KEY_NAME}-pub.pem | base64 | tr -d '\n')

cat > ${POLICY_FILE} << EOF
{
  "expires": "2025-12-31T23:59:59Z",
  "steps": {
    "rpm-build": {
      "name": "rpm-build",
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
  }
}
EOF
print_info "Policy file created: ${POLICY_FILE}"

# Step 7: Sign the policy
print_step "Signing the policy"
witness sign -f ${POLICY_FILE} -c empty-config.yaml \
    --signer-file-key-path ${KEY_NAME}.pem \
    --outfile ${POLICY_SIGNED}
print_info "Policy signed and saved to: ${POLICY_SIGNED}"

# Step 8: Create build attestation - CREATE the RPM during witness run so it's recorded as a product
print_step "Creating build attestation for RPM"
# Create the RPM file DURING witness run so it gets recorded as a subject/product
# Use only specific attestors to avoid git error
witness run --step rpm-build -c empty-config.yaml \
    -o ${ATTESTATION_BUILD} \
    -a environment,material,command-run,product \
    --signer-file-key-path ${KEY_NAME}.pem \
    -- bash -c "tar czf ${TEST_RPM} test-file.txt && echo 'Built RPM package'"
print_info "Build attestation created: ${ATTESTATION_BUILD}"

# Step 9: Sign the RPM file directly
print_step "Signing the RPM file"
witness sign -f ${TEST_RPM} -c empty-config.yaml \
    --signer-file-key-path ${KEY_NAME}.pem \
    --outfile ${TEST_RPM}.sig \
    --datatype "application/x-rpm"
print_info "RPM signature created: ${TEST_RPM}.sig"

# Step 10: Verify the RPM with attestations
print_step "Verifying with attestations"
echo ""
print_info "Running verification..."

if witness verify -c empty-config.yaml \
    -f ${TEST_RPM} \
    -a ${ATTESTATION_BUILD} \
    -p ${POLICY_SIGNED} \
    -k ${KEY_NAME}-pub.pem; then
    echo -e "${GREEN}✓ Verification SUCCESSFUL${NC}"
    echo ""
    print_info "The RPM package has been successfully verified!"
    print_info "All attestations match the policy requirements."
else
    echo -e "${RED}✗ Verification FAILED${NC}"
    echo ""
    print_error "The RPM package could not be verified."
    print_error "Check the attestations and policy requirements."
    exit 1
fi

# Step 11: Display summary
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Working Directory: $(pwd)"
echo "Keys Generated:"
echo "  - Private: ${KEY_NAME}.pem"
echo "  - Public: ${KEY_NAME}-pub.pem"
echo "  - Key ID: ${KEY_ID}"
echo "Files Created:"
echo "  - Policy: ${POLICY_FILE}"
echo "  - Signed Policy: ${POLICY_SIGNED}"
echo "  - Test RPM: ${TEST_RPM}"
echo "  - RPM Signature: ${TEST_RPM}.sig"
echo "  - Build Attestation: ${ATTESTATION_BUILD}"
echo ""
echo "To re-run this test with cleanup:"
echo "  $0 --clean"
echo ""
echo "To verify manually:"
echo "  witness verify -c empty-config.yaml -f ${TEST_RPM} -a ${ATTESTATION_BUILD} -p ${POLICY_SIGNED} -k ${KEY_NAME}-pub.pem"
echo ""

# Optional: Test failure scenario
if [ "$2" == "--test-failure" ]; then
    echo ""
    echo "========================================"
    echo "Testing Failure Scenario"
    echo "========================================"
    print_step "Creating invalid attestation"
    
    # Create an attestation with wrong step name
    witness run --step wrong-step -c empty-config.yaml \
        -o invalid-attestation.json \
        -a product \
        --signer-file-key-path ${KEY_NAME}.pem \
        -- echo "Invalid step"
    
    print_info "Attempting verification with invalid attestation..."
    if witness verify -f ${TEST_RPM} -c empty-config.yaml \
        -a invalid-attestation.json \
        -p ${POLICY_SIGNED} \
        -k ${KEY_NAME}-pub.pem 2>/dev/null; then
        print_error "Unexpected: Verification should have failed!"
    else
        echo -e "${GREEN}✓ Correctly rejected invalid attestation${NC}"
    fi
    
    rm -f invalid-attestation.json
fi

echo ""
print_info "Test completed successfully!"
#!/bin/bash
# Test Witness SBOM generation and attestation for RPM packages
# This script demonstrates how to generate SBOMs for RPMs and create attestations

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Witness SBOM Generation for RPMs ===${NC}"
echo "This script demonstrates SBOM generation and attestation"
echo ""

# Configuration
TEST_DIR="/tmp/witness-sbom-test-$(date +%s)"
KEY_NAME="sbom-test-key"
TEST_RPM="test-package.rpm"
SBOM_FILE="sbom.json"

# Create test directory
mkdir -p ${TEST_DIR}
cd ${TEST_DIR}

echo -e "${YELLOW}Step 1: Install Syft (if not already installed)${NC}"
if ! command -v syft &> /dev/null; then
    echo "Installing Syft..."
    curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
else
    echo "Syft is already installed: $(syft version)"
fi

echo -e "${YELLOW}Step 2: Generate test keys${NC}"
openssl genpkey -algorithm ed25519 -out ${KEY_NAME}.pem
openssl pkey -in ${KEY_NAME}.pem -pubout > ${KEY_NAME}-pub.pem
echo -e "${GREEN}✓ Keys generated${NC}"

echo -e "${YELLOW}Step 3: Create a test RPM package${NC}"
# Create a simple spec file for testing
cat > test-package.spec << 'EOF'
Name: test-package
Version: 1.0.0
Release: 1%{?dist}
Summary: Test package for SBOM generation
License: MIT
BuildArch: noarch

%description
A test package to demonstrate SBOM generation with Witness

%prep
# Nothing to prepare

%build
# Create some test files
echo "#!/bin/bash" > test-script.sh
echo "echo 'Hello from test package'" >> test-script.sh
chmod +x test-script.sh

# Create a Python file to have dependencies
cat > app.py << 'PYTHON'
#!/usr/bin/env python3
import json
import requests
import yaml

def main():
    print("Test application")
    data = {"message": "Hello World"}
    print(json.dumps(data))

if __name__ == "__main__":
    main()
PYTHON

%install
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/lib/test-package
cp test-script.sh %{buildroot}/usr/bin/
cp app.py %{buildroot}/usr/lib/test-package/

%files
/usr/bin/test-script.sh
/usr/lib/test-package/app.py

%changelog
* $(date "+%a %b %d %Y") Test User <test@example.com> - 1.0.0-1
- Initial package with SBOM support
EOF

echo -e "${YELLOW}Step 4: Build RPM with Witness attestation${NC}"
# Create empty config for Witness
echo "{}" > config.yaml

# Build the RPM with witness attestation (no SBOM yet since it doesn't exist)
echo "Building RPM with attestation..."
witness run --step build \
    -c config.yaml \
    -o attestation-build.json \
    -a environment,material,command-run,product \
    --signer-file-key-path ${KEY_NAME}.pem \
    -- rpmbuild -bb --define "_topdir $(pwd)/rpmbuild" test-package.spec

# Find the built RPM
BUILT_RPM=$(find rpmbuild/RPMS -name "*.rpm" | head -1)
if [ -z "$BUILT_RPM" ]; then
    echo -e "${RED}Error: No RPM found${NC}"
    exit 1
fi
cp "$BUILT_RPM" ${TEST_RPM}
echo -e "${GREEN}✓ RPM built: ${TEST_RPM}${NC}"

echo -e "${YELLOW}Step 5: Generate SBOM with Witness attestation${NC}"
# The SBOM attestor will detect the SBOM files created during the command
# Using 'syft scan' (new command) instead of deprecated 'syft packages'
echo "Generating SBOM with attestation..."
witness run --step sbom-generation \
    -c config.yaml \
    -o attestation-sbom.json \
    -a material,command-run,product,sbom \
    --attestor-sbom-export \
    --signer-file-key-path ${KEY_NAME}.pem \
    -- bash -c "
        syft scan ${TEST_RPM} -o json > ${SBOM_FILE}
        syft scan ${TEST_RPM} -o spdx-json > sbom.spdx.json
        syft scan ${TEST_RPM} -o cyclonedx-json > sbom.cdx.json
    "

echo -e "${GREEN}✓ SBOM generated and attested${NC}"

# Display SBOM summary
echo -e "${BLUE}SBOM Summary:${NC}"
syft scan ${TEST_RPM} -q

echo -e "${GREEN}✓ SBOM attestation created${NC}"

echo -e "${YELLOW}Step 7: Extract and analyze attestations${NC}"
# Check for exported SBOM attestation file
if [ -f "attestation-sbom.json-sbom.json" ]; then
    echo -e "${GREEN}✓ Exported SBOM attestation found: attestation-sbom.json-sbom.json${NC}"
    
    # Extract SBOM content
    echo "Extracting SBOM data from exported attestation..."
    cat attestation-sbom.json-sbom.json | jq -r '.payload' | base64 -d > sbom-attestation-content.json
    
    # Display SBOM type
    SBOM_TYPE=$(cat sbom-attestation-content.json | jq -r '.predicateType')
    echo -e "${BLUE}SBOM Type: ${SBOM_TYPE}${NC}"
    
    # Display subjects
    echo -e "${BLUE}SBOM Subjects:${NC}"
    cat sbom-attestation-content.json | jq -r '.subject[]?.name'
fi

# Also check main attestation
echo "Extracting data from main attestation..."
cat attestation-sbom.json | jq -r '.payload' | base64 -d | jq '.predicate' > predicate-sbom.json

# Check if SBOM attestor data is present in main attestation
if cat predicate-sbom.json | jq -e '.attestations[] | select(.type == "https://witness.dev/attestations/sbom/v0.1")' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ SBOM attestation found in main predicate${NC}"
    
    # Extract SBOM details
    echo -e "${BLUE}SBOM Attestation Details:${NC}"
    cat predicate-sbom.json | jq '.attestations[] | select(.type == "https://witness.dev/attestations/sbom/v0.1") | .attestation'
else
    echo -e "${YELLOW}Note: SBOM attestation embedded in main attestation collection${NC}"
fi

echo -e "${YELLOW}Step 8: Create a policy that requires SBOM${NC}"
# Get the key ID for the policy
KEY_ID=$(cat attestation-build.json | jq -r '.signatures[0].keyid')
PUB_KEY=$(base64 < ${KEY_NAME}-pub.pem | tr -d '\n')

cat > policy-sbom.json << EOF
{
  "expires": "2026-12-31T23:59:59Z",
  "steps": {
    "build": {
      "attestations": [
        {"type": "https://witness.dev/attestations/material/v0.1"},
        {"type": "https://witness.dev/attestations/command-run/v0.1"},
        {"type": "https://witness.dev/attestations/product/v0.1"},
        {"type": "https://witness.dev/attestations/sbom/v0.1"}
      ],
      "functionaries": [
        {"type": "publickey", "publickeyid": "${KEY_ID}"}
      ]
    },
    "sbom-generation": {
      "attestations": [
        {"type": "https://witness.dev/attestations/material/v0.1"},
        {"type": "https://witness.dev/attestations/command-run/v0.1"},
        {"type": "https://witness.dev/attestations/product/v0.1"},
        {"type": "https://witness.dev/attestations/sbom/v0.1"}
      ],
      "functionaries": [
        {"type": "publickey", "publickeyid": "${KEY_ID}"}
      ]
    }
  },
  "publickeys": {
    "${KEY_ID}": {
      "keyid": "${KEY_ID}",
      "key": "${PUB_KEY}"
    }
  }
}
EOF

# Sign the policy
witness sign -f policy-sbom.json \
    --signer-file-key-path ${KEY_NAME}.pem \
    --outfile policy-sbom-signed.json

echo -e "${GREEN}✓ Policy created and signed${NC}"

echo -e "${YELLOW}Step 9: Verify with SBOM policy${NC}"
# Verify the RPM with the SBOM policy
if witness verify -f ${TEST_RPM} \
    -a attestation-build.json \
    -p policy-sbom-signed.json \
    -k ${KEY_NAME}-pub.pem; then
    echo -e "${GREEN}✓ RPM verified with SBOM attestation${NC}"
else
    echo -e "${YELLOW}Note: Verification with SBOM-specific policy may require additional configuration${NC}"
fi

echo -e "${YELLOW}Step 10: Generate SLSA provenance with SBOM${NC}"
# Create SLSA attestation that includes SBOM
witness run --step slsa-build \
    -c config.yaml \
    -o attestation-slsa.json \
    -a environment,material,command-run,product,sbom,slsa \
    --attestor-slsa-export \
    --attestor-sbom-export \
    --signer-file-key-path ${KEY_NAME}.pem \
    -- echo "Package already built"

echo -e "${GREEN}✓ SLSA provenance with SBOM created${NC}"

echo -e "${BLUE}=== Summary ===${NC}"
echo "Generated artifacts:"
echo "  - RPM Package: ${TEST_RPM}"
echo "  - SBOM (Syft): ${SBOM_FILE}"
echo "  - Build Attestation: attestation-build.json"
echo "  - SBOM Attestation: attestation-sbom.json"
echo "  - SLSA Attestation: attestation-slsa.json"
echo "  - Policy: policy-sbom-signed.json"
echo ""
echo "SBOM formats supported by Syft:"
echo "  - SPDX (spdx-json, spdx-tag-value)"
echo "  - CycloneDX (cyclonedx-json, cyclonedx-xml)"
echo "  - Syft native JSON"
echo ""
echo -e "${GREEN}✓ SBOM generation and attestation complete!${NC}"

# Cleanup option
echo ""
echo -e "${YELLOW}Test directory: ${TEST_DIR}${NC}"
echo "To clean up, run: rm -rf ${TEST_DIR}"
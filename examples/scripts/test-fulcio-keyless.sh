#!/bin/bash

# Witness Fulcio (Keyless Signing) Test Script
# This demonstrates using Sigstore's Fulcio for keyless signing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WORKDIR="witness-fulcio-test"
TEST_RPM="test-package.rpm"
ATTESTATION_FULCIO="rpm-fulcio-attestation.json"
POLICY_FILE="fulcio-policy.json"
POLICY_SIGNED="fulcio-policy-signed.json"

# Fulcio Configuration
FULCIO_URL="https://fulcio.sigstore.dev"
REKOR_URL="https://rekor.sigstore.dev"
OIDC_ISSUER="https://oauth2.sigstore.dev/auth"
OIDC_CLIENT_ID="sigstore"

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

cleanup() {
    print_info "Cleaning up previous test files..."
    rm -f ${TEST_RPM} ${ATTESTATION_FULCIO}
    rm -f ${POLICY_FILE} ${POLICY_SIGNED}
    rm -f empty-config.yaml test-file.txt
    rm -f *.sig *.pem *.crt
}

# Main script
echo "================================================"
echo "Witness Fulcio (Keyless Signing) Test"
echo "================================================"
echo ""
print_info "This demonstrates keyless signing using Sigstore's Fulcio"
echo ""

# Step 1: Setup working directory
print_step "Setting up working directory"
mkdir -p ${WORKDIR}
cd ${WORKDIR}

# Optional cleanup
if [ "$1" == "--clean" ]; then
    cleanup
fi

# Step 2: Check for Fulcio connectivity
print_step "Checking Fulcio connectivity"
if curl -s --connect-timeout 2 ${FULCIO_URL}/api/v1/rootCert > /dev/null 2>&1; then
    print_success "Fulcio is accessible at ${FULCIO_URL}"
else
    print_error "Cannot reach Fulcio at ${FULCIO_URL}"
    print_info "This may be due to network restrictions"
fi

# Step 3: Create empty config
print_step "Creating configuration"
echo "{}" > empty-config.yaml

# Step 4: Create test content
print_step "Creating test content"
echo "Test RPM Package for Fulcio signing" > test-file.txt

# Step 5: Demonstrate Fulcio signing options
print_step "Available Fulcio signing methods"
echo ""
echo "Method 1: Interactive browser-based authentication (default)"
echo "  witness run --step rpm-build \\"
echo "    --signer-fulcio-url ${FULCIO_URL} \\"
echo "    --signer-fulcio-oidc-issuer ${OIDC_ISSUER} \\"
echo "    --signer-fulcio-oidc-client-id ${OIDC_CLIENT_ID} \\"
echo "    -- <command>"
echo ""
echo "Method 2: Using pre-obtained OIDC token"
echo "  witness run --step rpm-build \\"
echo "    --signer-fulcio-url ${FULCIO_URL} \\"
echo "    --signer-fulcio-token \$TOKEN \\"
echo "    -- <command>"
echo ""
echo "Method 3: Using GitHub Actions OIDC"
echo "  witness run --step rpm-build \\"
echo "    --signer-fulcio-url ${FULCIO_URL} \\"
echo "    --signer-fulcio-oidc-issuer https://token.actions.githubusercontent.com \\"
echo "    --signer-fulcio-token \$ACTIONS_ID_TOKEN_REQUEST_TOKEN \\"
echo "    -- <command>"
echo ""

# Step 6: Create policy for Fulcio
print_step "Creating policy for keyless verification"

# For Fulcio, we need to specify the certificate identity
cat > ${POLICY_FILE} << 'EOF'
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
          "type": "keyless",
          "certConstraints": {
            "commonname": "*",
            "dnsnames": [],
            "emails": [],
            "organizations": [],
            "uris": [],
            "roots": []
          }
        }
      ]
    }
  },
  "roots": {
    "fulcio": {
      "certificate": "",
      "intermediates": []
    }
  }
}
EOF

print_info "Policy created for keyless verification"

# Step 7: Test with local key signing (fallback if Fulcio not available)
print_step "Testing with local keys (Fulcio simulation)"

# Generate a temporary key for testing
openssl genpkey -algorithm ed25519 -out temp-key.pem 2>/dev/null
openssl pkey -in temp-key.pem -pubout > temp-pub.pem 2>/dev/null

# Create attestation with local key (simulating what Fulcio would do)
witness run --step rpm-build -c empty-config.yaml \
    -o ${ATTESTATION_FULCIO} \
    -a environment,material,command-run,product \
    --signer-file-key-path temp-key.pem \
    -- bash -c "tar czf ${TEST_RPM} test-file.txt && echo 'Built RPM package'" 2>/dev/null

if [ -f ${ATTESTATION_FULCIO} ]; then
    print_success "Attestation created (using local key for demo)"
else
    print_error "Failed to create attestation"
fi

# Step 8: Show Fulcio integration in CI/CD
print_step "Example: GitHub Actions with Fulcio"

cat > github-actions-example.yml << 'EOF'
name: Build and Sign with Fulcio
on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      id-token: write  # Required for OIDC
      contents: read
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install witness
      run: |
        curl -L https://github.com/testifysec/witness/releases/latest/download/witness_linux_amd64.tar.gz | tar -xz
        sudo mv witness /usr/local/bin/
    
    - name: Build and sign with Fulcio
      run: |
        witness run --step build \
          --signer-fulcio-url https://fulcio.sigstore.dev \
          --signer-fulcio-oidc-issuer https://token.actions.githubusercontent.com \
          --signer-fulcio-oidc-client-id sigstore \
          -o attestation.json \
          -a environment,material,command-run,product \
          -- make build
    
    - name: Upload to Rekor
      run: |
        witness sign -f attestation.json \
          --signer-fulcio-url https://fulcio.sigstore.dev \
          --rekor-server https://rekor.sigstore.dev \
          --outfile attestation.signed.json
EOF

print_info "GitHub Actions example created: github-actions-example.yml"

# Step 9: Show GitLab CI example
print_step "Example: GitLab CI with Fulcio"

cat > gitlab-ci-example.yml << 'EOF'
build-and-sign:
  image: alpine:latest
  id_tokens:
    SIGSTORE_ID_TOKEN:
      aud: sigstore
  script:
    - apk add curl tar
    - curl -L https://github.com/testifysec/witness/releases/latest/download/witness_linux_amd64.tar.gz | tar -xz
    - mv witness /usr/local/bin/
    - |
      witness run --step build \
        --signer-fulcio-url https://fulcio.sigstore.dev \
        --signer-fulcio-token $SIGSTORE_ID_TOKEN \
        -o attestation.json \
        -a environment,material,command-run,product \
        -- sh build.sh
EOF

print_info "GitLab CI example created: gitlab-ci-example.yml"

# Step 10: Demonstrate keyless verification concept
print_step "Keyless Verification Concept"

echo ""
echo "With Fulcio keyless signing:"
echo "1. Identity verified via OIDC (Google, GitHub, etc.)"
echo "2. Short-lived certificate issued by Fulcio"
echo "3. Signature created with ephemeral key"
echo "4. Certificate and signature stored in Rekor transparency log"
echo "5. Verification uses certificate chain, not long-lived keys"
echo ""

# Step 11: Show verification with certificate constraints
print_step "Certificate-based Verification"

cat > verify-keyless.sh << 'EOF'
#!/bin/bash
# Keyless verification example

witness verify \
  -f package.rpm \
  -a attestation.json \
  -p policy-signed.json \
  --signer-fulcio-url https://fulcio.sigstore.dev \
  --rekor-server https://rekor.sigstore.dev \
  --certificate-identity "user@example.com" \
  --certificate-oidc-issuer "https://accounts.google.com"
EOF

chmod +x verify-keyless.sh
print_info "Keyless verification script created: verify-keyless.sh"

# Step 12: Summary
echo ""
echo "================================================"
echo "Fulcio Integration Summary"
echo "================================================"
echo ""
echo "Key Benefits of Keyless Signing:"
echo "  ✓ No long-lived keys to manage"
echo "  ✓ Identity-based trust"
echo "  ✓ Automatic key rotation"
echo "  ✓ Transparency log integration"
echo "  ✓ Non-repudiation through Rekor"
echo ""
echo "Supported Identity Providers:"
echo "  • Google"
echo "  • GitHub"
echo "  • GitLab"
echo "  • Microsoft"
echo "  • Custom OIDC providers"
echo ""
echo "Files Created:"
echo "  - github-actions-example.yml"
echo "  - gitlab-ci-example.yml"
echo "  - verify-keyless.sh"
echo "  - ${POLICY_FILE}"
echo ""
echo "Next Steps:"
echo "1. Set up OIDC in your CI/CD platform"
echo "2. Configure Fulcio URL and parameters"
echo "3. Update policies for keyless verification"
echo "4. Integrate with Rekor for transparency"
echo ""

# Step 13: Test Fulcio API endpoints
print_step "Testing Sigstore Infrastructure"

echo -n "Fulcio API: "
if curl -s ${FULCIO_URL}/api/v1/rootCert > /dev/null 2>&1; then
    echo -e "${GREEN}Available${NC}"
else
    echo -e "${RED}Unavailable${NC}"
fi

echo -n "Rekor API: "
if curl -s ${REKOR_URL}/api/v1/log > /dev/null 2>&1; then
    echo -e "${GREEN}Available${NC}"
else
    echo -e "${RED}Unavailable${NC}"
fi

print_success "Fulcio integration examples completed!"
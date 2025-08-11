#!/bin/bash
# Validate all examples from the streamlined documentation

set -e

echo "================================================"
echo "Validating Streamlined Documentation Examples"
echo "================================================"
echo ""

# Create test directory
TEST_DIR=$(mktemp -d)
cd "${TEST_DIR}"
echo "Working directory: ${TEST_DIR}"
echo ""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run test
run_test() {
    local test_name="$1"
    echo "Testing: ${test_name}"
    if eval "$2" > /dev/null 2>&1; then
        echo "  ✓ Passed"
        ((TESTS_PASSED++))
    else
        echo "  ✗ Failed"
        ((TESTS_FAILED++))
    fi
    echo ""
}

# Test 1: Key generation
run_test "ED25519 key generation" "
    openssl genpkey -algorithm ed25519 -out test-key.pem &&
    openssl pkey -in test-key.pem -pubout > test-pub.pem &&
    [[ -f test-key.pem && -f test-pub.pem ]]
"

# Test 2: Basic witness command structure (if witness installed)
if command -v witness &> /dev/null; then
    run_test "Witness run command structure" "
        echo '{}' > config.yaml &&
        witness run --step test -c config.yaml -o test.json \
            -a environment --signer-file-key-path test-key.pem \
            -- echo 'test' &&
        [[ -f test.json ]]
    "
    
    # Test 3: Key ID extraction
    run_test "Key ID extraction" "
        KEY_ID=\$(jq -r '.signatures[0].keyid' test.json) &&
        [[ -n \"\${KEY_ID}\" && \"\${KEY_ID}\" != 'null' ]]
    "
    
    # Test 4: Policy creation
    run_test "Policy JSON creation" "
        KEY_ID=\$(jq -r '.signatures[0].keyid' test.json) &&
        PUB_KEY=\$(base64 < test-pub.pem | tr -d '\n') &&
        cat > policy.json << EOF
{
  \"expires\": \"2026-12-31T23:59:59Z\",
  \"steps\": {
    \"build\": {
      \"attestations\": [
        {\"type\": \"https://witness.dev/attestations/material/v0.1\"},
        {\"type\": \"https://witness.dev/attestations/command-run/v0.1\"},
        {\"type\": \"https://witness.dev/attestations/product/v0.1\"}
      ],
      \"functionaries\": [
        {\"type\": \"publickey\", \"publickeyid\": \"\${KEY_ID}\"}
      ]
    }
  },
  \"publickeys\": {
    \"\${KEY_ID}\": {\"keyid\": \"\${KEY_ID}\", \"key\": \"\${PUB_KEY}\"}
  }
}
EOF
        jq -e . policy.json
    "
    
    # Test 5: Policy signing
    run_test "Policy signing" "
        witness sign -f policy.json --signer-file-key-path test-key.pem \
            --outfile policy-signed.json &&
        [[ -f policy-signed.json ]]
    "
    
    # Test 6: Artifact creation with attestation
    run_test "Artifact with attestation" "
        witness run --step build -c config.yaml -o build.json \
            -a environment,material,command-run,product \
            --signer-file-key-path test-key.pem \
            -- bash -c 'tar czf package.rpm config.yaml && echo Built' &&
        [[ -f package.rpm && -f build.json ]]
    "
    
    # Test 7: Verification
    run_test "Witness verification" "
        witness verify -f package.rpm -a build.json \
            -p policy-signed.json -k test-pub.pem
    "
else
    echo "⚠️  Witness not installed - skipping witness-specific tests"
    echo ""
fi

# Test 8: Bundle directory structure
run_test "Air-gap bundle structure" "
    BUNDLE='test-bundle' &&
    mkdir -p \${BUNDLE}/{attestations,policies,certs,artifacts} &&
    [[ -d \${BUNDLE}/attestations && -d \${BUNDLE}/policies && 
       -d \${BUNDLE}/certs && -d \${BUNDLE}/artifacts ]]
"

# Test 9: Bundle creation script
run_test "Bundle script creation" "
    BUNDLE='test-bundle' &&
    cat > \${BUNDLE}/verify.sh << 'EOF'
#!/bin/bash
for rpm in artifacts/*.rpm; do
    echo \"Verifying \$rpm\"
done
EOF
    chmod +x \${BUNDLE}/verify.sh &&
    [[ -x \${BUNDLE}/verify.sh ]]
"

# Test 10: Bundle tarball
run_test "Bundle tarball creation" "
    BUNDLE='test-bundle' &&
    tar czf \${BUNDLE}.tar.gz \${BUNDLE}/ &&
    sha256sum \${BUNDLE}.tar.gz > \${BUNDLE}.tar.gz.sha256 &&
    [[ -f \${BUNDLE}.tar.gz && -f \${BUNDLE}.tar.gz.sha256 ]]
"

# Test 11: Checksum verification
run_test "Checksum verification" "
    sha256sum -c test-bundle.tar.gz.sha256
"

# Test 12: Policy JSON validation
run_test "Keyless policy structure" "
    cat > keyless-policy.json << 'EOF'
{
  \"expires\": \"2026-12-31T23:59:59Z\",
  \"steps\": {
    \"build\": {
      \"attestations\": [
        {\"type\": \"https://witness.dev/attestations/material/v0.1\"}
      ],
      \"functionaries\": [{
        \"type\": \"keyless\",
        \"certConstraints\": {
          \"emails\": [\"*@example.com\"],
          \"uris\": [\"https://github.com/org/*\"]
        }
      }]
    }
  },
  \"roots\": {
    \"fulcio\": \"BASE64_ROOT\"
  }
}
EOF
    jq -e '.steps.build.functionaries[0].certConstraints' keyless-policy.json
"

# Test 13: Compliance data extraction structure
run_test "Compliance JSON structure" "
    cat > mock-attestation.json << 'EOF'
{
  \"payload\": \"eyJwcmVkaWNhdGUiOnsic3RhcnRUaW1lIjoiMjAyNS0wOC0xMVQxMDowMDowMFoiLCJlbnZpcm9ubWVudCI6eyJVU0VSIjoiYnVpbGRlciJ9LCJtYXRlcmlhbHMiOlt7InVyaSI6ImZpbGU6Ly8vc3JjL21haW4uZ28ifV0sInByb2R1Y3RzIjpbeyJ1cmkiOiJmaWxlOi8vL2Rpc3QvYXBwLnJwbSJ9XSwiY29tbWFuZCI6WyJtYWtlIiwiYnVpbGQiXX19\"
}
EOF
    cat mock-attestation.json | jq -r '.payload' | base64 -d | jq -e '.predicate'
"

# Test 14: GitHub Actions YAML validation
run_test "GitHub Actions YAML structure" "
    cat > workflow.yml << 'EOF'
name: Build
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
    - uses: actions/checkout@v3
    - uses: testifysec/witness-run-action@v1
      with:
        step: build
        command: make build
EOF
    # Simple YAML validation - check for required fields
    grep -q 'id-token: write' workflow.yml &&
    grep -q 'witness-run-action' workflow.yml
"

# Test 15: TSA server connectivity (optional)
run_test "TSA server check" "
    # Just check if we can reach the TSA server
    curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://time.certum.pl | grep -q '200\|405' || true
"

# Cleanup
cd /
rm -rf "${TEST_DIR}"

# Summary
echo "================================================"
echo "Test Summary"
echo "================================================"
echo "✓ Passed: ${TESTS_PASSED}"
echo "✗ Failed: ${TESTS_FAILED}"
echo ""

if [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed. Please review."
    exit 1
fi
# SBOM and Security Attestations with Witness

## Overview

Witness provides comprehensive support for Software Bill of Materials (SBOM) generation and security scanning through specialized attestors. This guide covers SBOM creation, secret scanning, and vulnerability attestations for RPM packages.

## Available Security Attestors

| Attestor | Purpose | Type |
|----------|---------|------|
| **sbom** | Generate and attest SBOMs | postproduct |
| **secretscan** | Scan for leaked secrets/credentials | postproduct |
| **sarif** | Security vulnerability reports | postproduct |
| **vex** | Vulnerability Exploitability eXchange | postproduct |
| **slsa** | SLSA provenance generation | postproduct |

## SBOM Generation for RPMs

### 1. Basic SBOM Attestation

The SBOM attestor detects and attests SBOM files created during command execution:

```bash
# Generate SBOM and create attestation in one step
witness run --step sbom-generation \
  -o attestation.json \
  -a environment,material,command-run,product,sbom \
  --attestor-sbom-export \
  --signer-file-key-path key.pem \
  -- bash -c "syft scan package.rpm -o spdx-json > sbom.spdx.json"
```

The `--attestor-sbom-export` flag ensures the SBOM is exported as a separate attestation that can be queried independently. The SBOM attestor will automatically detect the SBOM file created by Syft.

### 2. Using Syft for Detailed SBOMs

Syft provides comprehensive SBOM generation with multiple format support:

```bash
# Install Syft
brew install syft  # macOS
# or
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s

# Generate SBOM in different formats with attestation
witness run --step sbom-generation \
  -o sbom-attestation.json \
  -a material,command-run,product,sbom \
  --attestor-sbom-export \
  --signer-file-key-path key.pem \
  -- bash -c "
    syft scan package.rpm -o spdx-json > sbom.spdx.json
    syft scan package.rpm -o cyclonedx-json > sbom.cdx.json
    syft scan package.rpm -o json > sbom.json
  "
```

### 3. SBOM Formats Supported

| Format | Description | Use Case |
|--------|-------------|----------|
| **SPDX** | ISO standard (ISO/IEC 5962:2021) | Compliance, legal |
| **CycloneDX** | OWASP standard | Security analysis |
| **Syft JSON** | Native Syft format | Detailed analysis |

## Secret Scanning Integration

### 1. Basic Secret Scanning

Scan for leaked credentials and secrets:

```bash
witness run --step security-scan \
  -o attestation.json \
  -a material,command-run,product,secretscan \
  --attestor-secretscan-fail-on-detection \
  --signer-file-key-path key.pem \
  -- rpmbuild -bb package.spec
```

### 2. Configure Allowlists

Exclude known safe patterns:

```bash
witness run --step build \
  -a material,command-run,product,secretscan \
  --attestor-secretscan-allowlist-regex "test.*key" \
  --attestor-secretscan-allowlist-stopword "example-api-key" \
  --attestor-secretscan-config-path gitleaks.toml \
  --signer-file-key-path key.pem \
  -- make build
```

### 3. Custom Gitleaks Configuration

Create a `gitleaks.toml` for custom rules:

```toml
title = "Custom Secret Scanning Rules"

[[rules]]
id = "rpm-signing-key"
description = "RPM signing key pattern"
regex = '''(?i)(rpm[_\-]?sign[_\-]?key)(.{0,20})?['\"]([0-9a-zA-Z]{32,45})['\"]'''
tags = ["key", "rpm"]

[[rules]]
id = "private-key-block"
description = "Private key block"
regex = '''-----BEGIN (RSA|EC|DSA|OPENSSH) PRIVATE KEY-----'''
tags = ["key", "private"]

[[allowlist]]
description = "Test keys are allowed"
paths = [
  "test/",
  "examples/",
  "*.test.sh"
]
```

## Complete SBOM Workflow Example

### Step 1: Create Build Script with SBOM

```bash
#!/bin/bash
# build-with-sbom.sh

# Configuration
PACKAGE_NAME="myapp"
VERSION="1.0.0"
KEY_PATH="signing-key.pem"

# Step 1: Build RPM with attestation
witness run --step build \
  -o attestation-build.json \
  -a environment,material,command-run,product \
  --enable-archivista \
  --signer-file-key-path ${KEY_PATH} \
  -- rpmbuild -bb ${PACKAGE_NAME}.spec

# Step 2: Generate SBOM with attestation
# The SBOM attestor will detect the SBOM files created by Syft
witness run --step sbom \
  -o attestation-sbom.json \
  -a material,command-run,product,sbom \
  --attestor-sbom-export \
  --enable-archivista \
  --signer-file-key-path ${KEY_PATH} \
  -- bash -c "
    syft packages ./RPMS/noarch/${PACKAGE_NAME}-${VERSION}.rpm -o json > sbom.json
    syft packages ./RPMS/noarch/${PACKAGE_NAME}-${VERSION}.rpm -o spdx-json > sbom-spdx.json
    syft packages ./RPMS/noarch/${PACKAGE_NAME}-${VERSION}.rpm -o cyclonedx-json > sbom-cyclonedx.json
  "

# Generate SLSA provenance
witness run --step provenance \
  -o attestation-slsa.json \
  -a slsa \
  --attestor-slsa-export \
  --enable-archivista \
  --signer-file-key-path ${KEY_PATH} \
  -- echo "SLSA provenance generated"
```

### Step 2: Create Policy Requiring SBOM

```json
{
  "expires": "2026-12-31T23:59:59Z",
  "steps": {
    "build": {
      "attestations": [
        {"type": "https://witness.dev/attestations/material/v0.1"},
        {"type": "https://witness.dev/attestations/command-run/v0.1"},
        {"type": "https://witness.dev/attestations/product/v0.1"},
        {"type": "https://witness.dev/attestations/sbom/v0.1"},
        {"type": "https://witness.dev/attestations/secretscan/v0.1"}
      ],
      "functionaries": [
        {"type": "publickey", "publickeyid": "KEY_ID"}
      ]
    },
    "sbom": {
      "attestations": [
        {"type": "https://witness.dev/attestations/sbom/v0.1"}
      ],
      "functionaries": [
        {"type": "publickey", "publickeyid": "KEY_ID"}
      ]
    }
  },
  "publickeys": {
    "KEY_ID": {
      "keyid": "KEY_ID",
      "key": "BASE64_PUBLIC_KEY"
    }
  }
}
```

### Step 3: Verification with SBOM

```bash
# Verify package with SBOM requirements
witness verify -f package.rpm \
  -a attestation-build.json \
  -a attestation-sbom.json \
  -p policy-signed.json \
  -k public-key.pem
```

## GitHub Actions with SBOM

```yaml
name: Build with SBOM
on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install Syft
      run: |
        curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s
        sudo mv syft /usr/local/bin/
    
    - name: Build with SBOM
      uses: testifysec/witness-run-action@v1
      with:
        step: build
        command: |
          rpmbuild -bb package.spec
          syft packages RPMS/noarch/*.rpm -o spdx-json > sbom.json
        attestations: "environment,material,command-run,product,sbom,secretscan"
    
    - name: Upload SBOM
      uses: actions/upload-artifact@v4
      with:
        name: sbom
        path: sbom.json
    
    - name: Security Scan
      uses: testifysec/witness-run-action@v1
      with:
        step: security
        command: |
          trivy fs --format sarif -o security.sarif .
          grype RPMS/noarch/*.rpm -o json > vulnerabilities.json
        attestations: "sarif,vex"
```

## Querying SBOM Attestations

### From Archivista

```bash
# Query by package digest
curl -X POST https://archivista.testifysec.io/query \
  -H "Content-Type: application/json" \
  -d '{"subject": {"digest": {"sha256": "PACKAGE_HASH"}}}'

# Extract SBOM from attestation
ATTESTATION_ID="abc123..."
curl https://archivista.testifysec.io/${ATTESTATION_ID} | \
  jq -r '.payload' | base64 -d | \
  jq '.predicate.attestations[] | select(.type == "https://witness.dev/attestations/sbom/v0.1")'
```

### From Local Attestation

```bash
# Extract SBOM data
cat attestation.json | jq -r '.payload' | base64 -d | \
  jq '.predicate.attestations[] | select(.type == "https://witness.dev/attestations/sbom/v0.1") | .attestation'

# List all components
cat attestation.json | jq -r '.payload' | base64 -d | \
  jq '.predicate.attestations[] | select(.type == "https://witness.dev/attestations/sbom/v0.1") | .attestation.components[].name'
```

## VEX (Vulnerability Exploitability eXchange)

Document vulnerability status and mitigations:

```json
{
  "@context": "https://openvex.dev/ns",
  "@id": "https://example.com/vex/2024-001",
  "author": "Security Team",
  "timestamp": "2024-01-15T10:00:00Z",
  "version": "1",
  "statements": [
    {
      "vulnerability": "CVE-2024-12345",
      "products": ["pkg:rpm/myapp@1.0.0"],
      "status": "not_affected",
      "justification": "vulnerable_code_not_in_execute_path"
    }
  ]
}
```

Attest VEX document:

```bash
witness run --step vex \
  -o attestation-vex.json \
  -a material,product,vex \
  --signer-file-key-path key.pem \
  -- echo "VEX document created"
```

## Best Practices

1. **Always Generate SBOMs**: Include SBOM attestation in every build
2. **Multiple Formats**: Generate both SPDX and CycloneDX for compatibility
3. **Secret Scanning**: Enable fail-on-detection in CI/CD
4. **VEX Documentation**: Document all known vulnerabilities and mitigations
5. **Policy Enforcement**: Require SBOM and security attestations in policies
6. **Archivista Storage**: Store all attestations for audit trails
7. **Regular Updates**: Keep Syft and security tools updated

## Troubleshooting

| Issue | Solution |
|-------|----------|
| SBOM attestor not found | Update Witness to latest version |
| Syft installation fails | Use brew or download binary directly |
| Secret detection false positives | Configure allowlist patterns |
| Large SBOM files | Use compression or store separately |
| Missing dependencies in SBOM | Ensure build environment has all packages |

## Example: Complete RPM Build with Security

```bash
#!/bin/bash
# secure-rpm-build.sh

set -e

# Build with all security attestations
witness run --step secure-build \
  -o attestation-complete.json \
  -a environment,material,command-run,product,sbom,secretscan,sarif \
  --attestor-sbom-export \
  --attestor-secretscan-fail-on-detection \
  --attestor-secretscan-config-path security.toml \
  --attestor-slsa-export \
  --enable-archivista \
  --signer-fulcio-url https://fulcio.sigstore.dev \
  --timestamp-servers "http://time.certum.pl" \
  -- bash -c "
    rpmbuild -bb package.spec
    syft packages RPMS/noarch/*.rpm -o spdx-json > sbom.json
    grype RPMS/noarch/*.rpm -o json > vulns.json
    trivy fs --format sarif -o security.sarif .
  "

echo "Build complete with full security attestations"
```

## Resources

- **Syft Documentation**: https://github.com/anchore/syft
- **SPDX Specification**: https://spdx.dev/
- **CycloneDX**: https://cyclonedx.org/
- **OpenVEX**: https://openvex.dev/
- **Gitleaks**: https://github.com/gitleaks/gitleaks
- **Grype**: https://github.com/anchore/grype
- **Trivy**: https://github.com/aquasecurity/trivy

---

*Last Updated: 2025-08-11*  
*Version: 1.0*
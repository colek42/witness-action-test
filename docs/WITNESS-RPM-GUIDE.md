# Witness Framework: Enterprise RPM Supply Chain Security Guide

## Executive Summary

Witness provides cryptographic attestation for software supply chains, ensuring package integrity and build provenance through in-toto attestations. This guide covers RPM signing, keyless authentication, air-gap deployments, and enterprise integration patterns.

**Key Features:**
- ✅ RPM attestation without GPG dependency
- ✅ Keyless signing via Fulcio with TSA counter-signing
- ✅ Full offline verification for air-gapped environments
- ✅ Multi-KMS support (AWS, Azure, GCP, Vault)
- ✅ GitHub Actions integration via witness-run-action
- ✅ NIST compliance metadata generation

## Quick Start

### 1. Basic RPM Signing

```bash
# Generate keys
openssl genpkey -algorithm ed25519 -out witness-key.pem
openssl pkey -in witness-key.pem -pubout > witness-pub.pem

# Create attestation during RPM build
witness run --step build \
  -o attestation.json \
  -a environment,material,command-run,product \
  --signer-file-key-path witness-key.pem \
  -- rpmbuild -bb package.spec

# Verify
witness verify -f package.rpm \
  -a attestation.json \
  -p policy.json \
  -k witness-pub.pem
```

### 2. Keyless with GitHub Actions

```yaml
- name: Build and Sign
  uses: testifysec/witness-run-action@v1
  with:
    step: build
    command: rpmbuild -bb package.spec
```

## Architecture

```
Source → Build Process → Attestation → Verification
         ↓                ↓             ↓
         Materials        Products      Policy Check
         Commands         Signatures    Trust Validation
         Environment      Timestamps    Offline Support
```

## Implementation Guide

### Key-Based Signing

<details>
<summary>Complete key-based workflow</summary>

```bash
#!/bin/bash
# 1. Generate ED25519 keys
openssl genpkey -algorithm ed25519 -out key.pem
openssl pkey -in key.pem -pubout > pub.pem

# 2. Get key ID
echo "{}" > config.yaml
witness run --step test -c config.yaml -o test.json \
  -a environment --signer-file-key-path key.pem -- echo test
KEY_ID=$(jq -r '.signatures[0].keyid' test.json)

# 3. Create policy
PUB_KEY=$(base64 < pub.pem | tr -d '\n')
cat > policy.json << EOF
{
  "expires": "2026-12-31T23:59:59Z",
  "steps": {
    "build": {
      "attestations": [
        {"type": "https://witness.dev/attestations/material/v0.1"},
        {"type": "https://witness.dev/attestations/command-run/v0.1"},
        {"type": "https://witness.dev/attestations/product/v0.1"}
      ],
      "functionaries": [
        {"type": "publickey", "publickeyid": "${KEY_ID}"}
      ]
    }
  },
  "publickeys": {
    "${KEY_ID}": {"keyid": "${KEY_ID}", "key": "${PUB_KEY}"}
  }
}
EOF

# 4. Sign policy
witness sign -f policy.json --signer-file-key-path key.pem \
  --outfile policy-signed.json

# 5. Build with attestation (with Archivista)
witness run --step build -c config.yaml -o attestation.json \
  -a environment,material,command-run,product \
  --enable-archivista \
  --archivista-server https://archivista.testifysec.io \
  --signer-file-key-path key.pem \
  -- rpmbuild -bb package.spec

# 6. Verify
witness verify -f package.rpm -a attestation.json \
  -p policy-signed.json -k pub.pem
```

</details>

### Keyless Signing (Fulcio + TSA)

**Key Insight**: Uses TSA counter-signing instead of Rekor transparency logs for offline verification.

<details>
<summary>Fulcio keyless workflow</summary>

```bash
# Interactive (browser auth)
witness run --step build \
  --signer-fulcio-url https://fulcio.sigstore.dev \
  --signer-fulcio-oidc-issuer https://oauth2.sigstore.dev/auth \
  --signer-fulcio-oidc-client-id sigstore \
  --timestamp-servers "http://time.certum.pl" \
  -o attestation.json \
  -a environment,material,command-run,product \
  -- rpmbuild -bb package.spec

# GitHub Actions (automatic OIDC)
# IMPORTANT: Requires permissions: id-token: write
witness run --step build \
  --signer-fulcio-url https://fulcio.sigstore.dev \
  --signer-fulcio-oidc-issuer https://token.actions.githubusercontent.com \
  --signer-fulcio-oidc-client-id sigstore \
  --timestamp-servers "http://time.certum.pl" \
  --enable-archivista \
  --archivista-server https://archivista.testifysec.io \
  -o attestation.json \
  -a environment,material,command-run,product \
  -- rpmbuild -bb package.spec
```

**Certificate Validity**: 10 minutes (validated 2025-08-11)  
**TSA Servers** (tested):
- ✅ `http://time.certum.pl` (recommended)
- ✅ `http://timestamp.digicert.com`
- ⚠️ `http://freetsa.org/tsr` (variable)

</details>

## GitHub Actions Integration

### witness-run-action

The official GitHub Action provides zero-configuration attestation with automatic Sigstore and Archivista integration.

**Live Example**: View a working implementation at [github.com/colek42/witness-action-test](https://github.com/colek42/witness-action-test)

```yaml
name: Build with Attestation
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      id-token: write    # REQUIRED for Fulcio OIDC
      contents: read     # Access repository
      packages: write    # If publishing containers
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Test with Default Settings
      uses: testifysec/witness-run-action@v1
      with:
        step: test
        command: make test
        # Default settings (no need to specify):
        # enable-sigstore: true     # Fulcio signing enabled
        # enable-archivista: true   # Storage enabled
        # archivista-server: https://archivista.testifysec.io
    
    - name: Build with Custom Archivista
      uses: testifysec/witness-run-action@v1
      with:
        step: build
        command: make build
        archivista-server: https://archivista.internal.com  # Optional: custom server
    
    - name: Package without Archivista
      uses: testifysec/witness-run-action@v1
      with:
        step: package
        command: rpmbuild -bb package.spec
        enable-archivista: false  # Disable if needed (keeps attestation local only)
    
    - name: Full Control Example
      uses: testifysec/witness-run-action@v1
      with:
        step: release
        command: make release
        enable-sigstore: true      # Explicitly enable (default)
        enable-archivista: true    # Explicitly enable (default)
        archivista-server: https://archivista.testifysec.io
```

**Default Behavior**:
- ✅ `enable-sigstore: true` - Automatic Fulcio signing via GitHub OIDC
- ✅ `enable-archivista: true` - Automatic storage to public Archivista
- ✅ FreeTSA timestamping included
- ✅ No configuration needed for standard use

**Critical Requirements**:
1. **Must set** `permissions: id-token: write` for OIDC token
2. **Sigstore** requires internet access to Fulcio
3. **Archivista** stores attestations publicly by default (use custom server for private)

**Verified Example**: See the complete workflow at [witness-action-test/.github/workflows/witness-test.yml](https://github.com/colek42/witness-action-test/blob/main/.github/workflows/witness-test.yml) with [successful run results](https://github.com/colek42/witness-action-test/actions/runs/16889563525)

## Multi-KMS Support

| KMS | Configuration | Air-Gap Support |
|-----|--------------|-----------------|
| **Fulcio** | `--signer-fulcio-url https://fulcio.sigstore.dev` | ✅ Yes (with TSA) |
| **AWS KMS** | `--signer-kms-ref awskms:///arn:aws:kms:...` | ⚠️ Limited |
| **Azure** | `--signer-kms-ref azurekms://vault.azure.net/...` | ⚠️ Limited |
| **GCP** | `--signer-kms-ref gcpkms://projects/.../keys/...` | ⚠️ Limited |
| **Vault** | `--signer-kms-ref hashivault://key-name` | ✅ Yes |
| **File** | `--signer-file-key-path key.pem` | ✅ Yes |

## Air-Gap Bundle Export

Create self-contained verification bundles for offline environments:

```bash
#!/bin/bash
# create-bundle.sh
BUNDLE="release-$(date +%Y%m%d)"
mkdir -p ${BUNDLE}/{attestations,policies,certs,artifacts}

# Copy artifacts and attestations
cp *.rpm ${BUNDLE}/artifacts/
cp *.json ${BUNDLE}/attestations/

# Export certificates
curl -s https://fulcio.sigstore.dev/api/v1/rootCert > ${BUNDLE}/certs/fulcio.pem
curl -s http://time.certum.pl/cert > ${BUNDLE}/certs/tsa.pem

# Create verification script
cat > ${BUNDLE}/verify.sh << 'EOF'
#!/bin/bash
for rpm in artifacts/*.rpm; do
    witness verify -f "$rpm" \
        -a "attestations/$(basename $rpm .rpm).json" \
        -p policies/policy.json \
        --verifier-fulcio-roots certs/fulcio.pem
done
EOF

chmod +x ${BUNDLE}/verify.sh
tar czf ${BUNDLE}.tar.gz ${BUNDLE}/
sha256sum ${BUNDLE}.tar.gz > ${BUNDLE}.tar.gz.sha256
```

## Enterprise Features

### Archivista Integration

Centralized attestation storage with query capabilities:

```bash
# Enable during attestation (stores attestation remotely)
witness run --step build \
  --enable-archivista \
  --archivista-server https://archivista.testifysec.io \
  --signer-file-key-path key.pem \
  -o attestation.json \
  -a environment,material,command-run,product \
  -- make build

# Query attestations by subject digest
curl -X POST https://archivista.testifysec.io/query \
  -H "Content-Type: application/json" \
  -d '{"subject": {"digest": {"sha256": "abc123..."}}}'

# Self-hosted Archivista
docker run -d -p 8080:8080 \
  ghcr.io/testifysec/archivista:latest
  
# Use with self-hosted
witness run --step build \
  --enable-archivista \
  --archivista-server http://localhost:8080 \
  --signer-file-key-path key.pem \
  -- make build
```

### NIST Compliance Support

Witness attestations provide rich metadata that can be mapped to compliance controls:

```bash
# Extract compliance-relevant metadata
cat attestation.json | jq -r '.payload' | base64 -d | jq '{
  build_time: .predicate.startTime,
  builder: .predicate.environment.USER,
  materials: [.predicate.materials[].uri],
  products: [.predicate.products[].uri],
  command: .predicate.command | join(" ")
}'
```

**TestifySec Enterprise**: Automatically maps policy-as-code, configuration-as-code, and build/test metadata to NIST and other compliance frameworks, providing continuous compliance validation.

### GPG Migration Path

Transition from GPG to Witness:

```bash
# Phase 1: Dual signing
rpmsign --key-id KEY_ID package.rpm  # Legacy GPG
witness run --step build ... -- echo "Already signed"  # Add attestation

# Phase 2: Verification wrapper
if witness verify ... || rpm --checksig ...; then
    echo "Package verified"
fi

# Phase 3: Pure Witness (no GPG)
witness run --step build ... -- rpmbuild -bb package.spec
```

## Policy Examples

### Basic Policy Template

```json
{
  "expires": "2026-12-31T23:59:59Z",
  "steps": {
    "build": {
      "attestations": [
        {"type": "https://witness.dev/attestations/material/v0.1"},
        {"type": "https://witness.dev/attestations/command-run/v0.1"},
        {"type": "https://witness.dev/attestations/product/v0.1"}
      ],
      "functionaries": [
        {"type": "publickey", "publickeyid": "KEY_ID"}
      ]
    }
  },
  "publickeys": {
    "KEY_ID": {"keyid": "KEY_ID", "key": "BASE64_PUBLIC_KEY"}
  }
}
```

### Keyless Policy

```json
{
  "expires": "2026-12-31T23:59:59Z",
  "steps": {
    "build": {
      "attestations": [...],
      "functionaries": [{
        "type": "keyless",
        "certConstraints": {
          "emails": ["*@example.com"],
          "uris": ["https://github.com/org/*"]
        }
      }]
    }
  },
  "roots": {
    "fulcio": "BASE64_FULCIO_ROOT"
  }
}
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "predicate type is not a collection" | Use individual attestation types in policy |
| "no verifiers present" | Create artifacts during witness run |
| "repository does not exist" | Use `-a` flag to specify attestors |
| "signature outside validity" | Ensure TSA counter-signing enabled |
| "OIDC token expired" | Re-authenticate or use fresh token |

## Production Checklist

- [ ] Choose signing method (keys vs keyless)
- [ ] Configure TSA for timestamp proof
- [ ] Set up Archivista for attestation storage
- [ ] Create and sign verification policies
- [ ] Implement air-gap bundle export
- [ ] Test verification workflow
- [ ] Document recovery procedures

## OpenCHAMI Integration Example

Complete workflow for HPC environments:

```yaml
# .github/workflows/openchami-witness.yml
name: OpenCHAMI Release
on:
  push:
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: write
    
    steps:
    - uses: actions/checkout@v3
    
    - uses: actions/setup-go@v4
      with:
        go-version: '1.21'
    
    - name: Test
      uses: testifysec/witness-run-action@v1
      with:
        step: test
        command: go test ./...
    
    - name: Build
      uses: testifysec/witness-run-action@v1
      with:
        step: build
        command: goreleaser build --clean
    
    - name: Package RPM
      uses: testifysec/witness-run-action@v1
      with:
        step: package
        command: |
          rpmbuild -bb \
            --define "version ${GITHUB_REF_NAME#v}" \
            ochami.spec
```

## Resources

- **Documentation**: https://witness.dev
- **Source Code**: https://github.com/testifysec/witness
- **GitHub Action**: https://github.com/testifysec/witness-run-action
- **Working Example**: https://github.com/colek42/witness-action-test
- **Archivista**: https://github.com/testifysec/archivista
- **Support**: https://testifysec.com

---

*Version 3.0 - Streamlined Edition*  
*Last Updated: 2025-08-11*  
*Status: Production Ready*
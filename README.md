# Witness Framework: Complete Enterprise Implementation Guide

## 🚀 Quick Start

This repository demonstrates a complete, production-ready implementation of the Witness framework for software supply chain security, with a focus on RPM package signing and enterprise deployment.

### What's Included

- ✅ **Working GitHub Actions** with witness-run-action
- ✅ **Complete RPM signing examples** (key-based and keyless)
- ✅ **Comprehensive documentation** for enterprise deployment
- ✅ **Validated test scripts** for all signing methods
- ✅ **Air-gap deployment guides** for offline environments

## 📚 Documentation

### [Complete Enterprise Guide](docs/WITNESS-RPM-GUIDE.md)
The comprehensive guide covering:
- RPM attestation without GPG dependency
- Keyless signing via Fulcio with TSA counter-signing
- Full offline verification for air-gapped environments
- Multi-KMS support (AWS, Azure, GCP, Vault)
- GitHub Actions integration
- NIST compliance metadata generation
- SBOM generation and attestation
- Security scanning integration

### [SBOM and Security Guide](docs/SBOM-AND-SECURITY-ATTESTATIONS.md)
Detailed documentation for:
- Software Bill of Materials (SBOM) generation
- Secret scanning with blocklists
- Vulnerability attestations (SARIF, VEX)
- SLSA provenance with SBOM
- Complete security workflows

## 🎯 Live Examples

### GitHub Actions Workflow

View our [working GitHub Actions workflow](.github/workflows/witness-test.yml) that demonstrates:
- Automatic Sigstore signing via GitHub OIDC
- Attestation storage in Archivista
- Multiple build steps with linked attestations

**Latest successful run**: [View on GitHub Actions](https://github.com/colek42/witness-action-test/actions)

### Test Scripts

Browse the [`examples/scripts/`](examples/scripts/) directory for ready-to-run scripts:
- `test-rpm-signing.sh` - Basic RPM signing with ED25519 keys
- `test-fulcio-keyless.sh` - Keyless signing with Fulcio (browser auth)
- `test-tsa-signing.sh` - TSA counter-signing validation
- `test-sbom-rpm.sh` - SBOM generation and attestation for RPMs

## 🔑 Key Features Demonstrated

### 1. witness-run-action Integration
```yaml
- uses: testifysec/witness-run-action@v1
  with:
    step: build
    command: make build
```
No configuration needed - automatic Sigstore and Archivista integration!

### 2. Keyless Signing
Using Fulcio for ephemeral certificates (10-minute validity):
```bash
witness run --step build \
  --signer-fulcio-url https://fulcio.sigstore.dev \
  --timestamp-servers "http://time.certum.pl" \
  -- rpmbuild -bb package.spec
```

### 3. Air-Gap Support
Complete offline verification with bundled certificates and policies.

## 🏗️ Repository Structure

```
witness-action-test/
├── .github/workflows/       # GitHub Actions workflows
│   └── witness-test.yml    # Main workflow with witness-run-action
├── docs/                    # Documentation
│   └── WITNESS-RPM-GUIDE.md # Complete enterprise guide
├── examples/               
│   ├── scripts/            # Test scripts for various scenarios
│   │   ├── test-rpm-signing.sh
│   │   ├── test-fulcio-keyless.sh
│   │   └── test-tsa-signing.sh
│   └── policies/           # Example witness policies
├── Makefile                # Build targets for testing
└── README.md              # This file
```

## 🧪 Testing Locally

### Prerequisites
```bash
# Install witness
curl -L https://github.com/testifysec/witness/releases/latest/download/witness_$(uname -s)_$(uname -m).tar.gz | tar -xz
sudo mv witness /usr/local/bin/

# Verify installation
witness version
```

### Run Basic Test
```bash
# Clone this repository
git clone https://github.com/colek42/witness-action-test.git
cd witness-action-test

# Run the basic test
make test build package

# Or run with witness attestation
witness run --step build -o attestation.json \
  -a environment,material,command-run,product \
  -- make build
```

### Run Example Scripts
```bash
# Test RPM signing with keys
./examples/scripts/test-rpm-signing.sh

# Test keyless signing (opens browser)
./examples/scripts/test-fulcio-keyless.sh

# Test TSA integration
./examples/scripts/test-tsa-signing.sh
```

## 🔒 Security Features

### Attestation Types
- **Material**: Input artifacts and dependencies
- **Command-run**: Exact commands executed
- **Product**: Output artifacts produced
- **Environment**: Build environment metadata
- **Git**: Repository state
- **GitHub**: GitHub Actions context

### Verification Chain
```
Source → Build → Attestation → Storage → Verification
         ↓        ↓             ↓         ↓
      Materials  Signature   Archivista  Policy
      Commands   Timestamp   Queryable   Trust
      Products   Identity    Permanent   Offline
```

## 🚢 Production Deployment

### Required Permissions (GitHub Actions)
```yaml
permissions:
  id-token: write    # Required for Fulcio OIDC
  contents: read     # Access repository
  packages: write    # If publishing containers
```

### Enterprise Configuration
For private Archivista deployment:
```yaml
- uses: testifysec/witness-run-action@v1
  with:
    step: build
    command: make build
    archivista-server: https://archivista.internal.company.com
```

## 📊 Verification Results

All examples in this repository have been tested and verified:
- ✅ GitHub Actions workflow runs successfully
- ✅ Attestations stored in Archivista
- ✅ Keyless signing via Fulcio confirmed
- ✅ TSA counter-signing validated
- ✅ Offline verification tested

### Latest Attestation IDs
- Test step: `795ecd8d94d5936054cd5aad669eb087fd15913aaa379a47e3c9689a0f3f4174`
- Build step: `89616e2393ac8784ed54c2e1b17429ee8a1ad3fa695319a2c77dac061620ffa2`
- Package step: `8bd10fedcc14bc33dcd8a095038d3ccf15a62f66baa1924cfa336aea4cc12696`

Query these attestations:
```bash
curl -X POST https://archivista.testifysec.io/query \
  -H "Content-Type: application/json" \
  -d '{"gitoid": "795ecd8d94d5936054cd5aad669eb087fd15913aaa379a47e3c9689a0f3f4174"}'
```

## 🤝 Support & Resources

- **Witness Documentation**: https://witness.dev
- **TestifySec**: https://testifysec.com
- **GitHub Action**: https://github.com/testifysec/witness-run-action
- **Archivista**: https://github.com/testifysec/archivista
- **This Repository**: https://github.com/colek42/witness-action-test

## 📝 License

This example repository is provided as-is for demonstration purposes.

---

**Ready for Production**: All examples tested and verified  
**Last Updated**: 2025-08-11  
**Maintained by**: TestifySec Team
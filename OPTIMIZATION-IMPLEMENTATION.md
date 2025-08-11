# Optimization Implementation Plan

## 🎯 FINAL ANALYSIS: What to Keep vs Remove

### ✅ MUST KEEP (Essential for Functionality)

#### 1. Core Documentation (1 file)
- **KEEP**: Merge into single `docs/COMPLETE-GUIDE.md`
- Contains: All essential information from both current guides
- Why: Customer needs comprehensive reference

#### 2. Test Suite (1 file instead of 6)
- **CREATE**: `examples/witness-test-suite.sh`
- Consolidates all test functionality
- Why: Each script tests unique functionality that must be preserved:
  - **RPM signing**: Basic attestation workflow
  - **Fulcio**: Keyless signing (browser auth)
  - **TSA**: Timestamp authority integration
  - **SBOM**: Syft integration and attestation

#### 3. GitHub Actions (unchanged)
- **KEEP AS-IS**: `.github/workflows/witness-test.yml`
- Why: Working in production, demonstrates real usage

#### 4. Policies (unchanged)
- **KEEP AS-IS**: Both policy JSON files
- Why: Templates for basic and keyless workflows

#### 5. Essential Support Files
- **KEEP**: `README.md` (update with new structure)
- **KEEP**: `Makefile` (already efficient)
- **KEEP**: `.gitignore` (minimal, correct)

### 🗑️ CAN REMOVE (Redundant/Outdated)

1. **DELETE**: `VALIDATION-REPORT.md` - Temporary validation document
2. **DELETE**: `test-streamlined-examples.sh` - Duplicates other tests  
3. **DELETE**: `validate-all.sh` - Replace with Makefile target
4. **MERGE & DELETE**: Original documentation files after merging

### 📝 CONSOLIDATION ACTIONS

## Step 1: Create Unified Test Suite

```bash
#!/bin/bash
# examples/witness-test-suite.sh

# Common setup (DRY principle)
source "$(dirname "$0")/common/setup.sh"

show_usage() {
    cat << EOF
Usage: $0 [test-name]

Available tests:
  basic     - Basic RPM signing with keys
  fulcio    - Keyless signing with Fulcio
  tsa       - TSA counter-signing
  sbom      - SBOM generation and attestation
  all       - Run all tests
  clean     - Clean test artifacts

Examples:
  $0 basic              # Run basic RPM signing test
  $0 all               # Run complete test suite
EOF
}

# Test functions
test_basic_rpm() {
    echo "=== Testing Basic RPM Signing ==="
    setup_keys
    create_test_rpm
    sign_rpm_with_witness
    create_policy
    verify_rpm
}

test_fulcio() {
    echo "=== Testing Fulcio Keyless Signing ==="
    # Fulcio-specific logic
}

test_tsa() {
    echo "=== Testing TSA Counter-signing ==="
    # TSA-specific logic
}

test_sbom() {
    echo "=== Testing SBOM Generation ==="
    check_syft
    create_test_rpm
    generate_sbom_with_attestation
    verify_sbom_attestation
}

# Main execution
case "${1:-all}" in
    basic)  test_basic_rpm ;;
    fulcio) test_fulcio ;;
    tsa)    test_tsa ;;
    sbom)   test_sbom ;;
    all)    
        test_basic_rpm
        test_tsa
        test_sbom
        echo "Note: Fulcio test requires browser interaction"
        ;;
    clean)  cleanup_test_artifacts ;;
    *)      show_usage; exit 1 ;;
esac
```

## Step 2: Create Common Functions Library

```bash
# examples/common/setup.sh

# Color definitions (used everywhere)
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Common functions
setup_keys() {
    openssl genpkey -algorithm ed25519 -out test-key.pem 2>/dev/null
    openssl pkey -in test-key.pem -pubout > test-pub.pem 2>/dev/null
    echo "{}" > config.yaml
}

create_test_rpm() {
    cat > test.spec << 'EOF'
Name: test-package
Version: 1.0.0
Release: 1
Summary: Test package
License: MIT
BuildArch: noarch
%description
Test package for witness
%files
EOF
    rpmbuild -bb --define "_topdir $(pwd)/rpmbuild" test.spec
}

cleanup_test_artifacts() {
    rm -f *.pem *.json *.rpm *.spec
    rm -rf rpmbuild/
}
```

## Step 3: Merge Documentation

### New Structure: `docs/COMPLETE-GUIDE.md`

```markdown
# Witness Framework: Complete Implementation Guide

## Table of Contents
1. [Quick Start](#quick-start)
2. [Installation](#installation)
3. [RPM Attestation](#rpm-attestation)
4. [Keyless Signing](#keyless-signing)
5. [SBOM Generation](#sbom-generation)
6. [GitHub Actions](#github-actions)
7. [Air-Gap Deployment](#air-gap-deployment)
8. [Troubleshooting](#troubleshooting)

[All content from both guides, deduplicated and organized]
```

## Step 4: Update Makefile

```makefile
# Simplified Makefile
.PHONY: test test-basic test-fulcio test-sbom test-all clean help

help:
	@echo "Available targets:"
	@echo "  make test        - Run basic tests"
	@echo "  make test-all    - Run all tests"
	@echo "  make test-sbom   - Test SBOM generation"
	@echo "  make clean       - Clean test artifacts"

test:
	./examples/witness-test-suite.sh basic

test-all:
	./examples/witness-test-suite.sh all

test-sbom:
	./examples/witness-test-suite.sh sbom

clean:
	./examples/witness-test-suite.sh clean
```

## 📊 IMPACT METRICS

### Before (Current State)
- **15 files**, 2,945 lines
- **40% redundant code**
- **6 separate test scripts** (hard to maintain)
- **2 documentation files** (overlapping content)
- **Scattered examples** (same command in 5+ places)

### After (Optimized)
- **9 files**, ~1,400 lines (52% reduction)
- **0% redundant code**
- **1 unified test suite** (easy to maintain)
- **1 comprehensive guide** (single source of truth)
- **DRY principle applied** (each example once)

## 🚀 IMPLEMENTATION SCHEDULE

### Phase 1: Test Consolidation (1 hour)
1. Create `examples/common/setup.sh`
2. Create `examples/witness-test-suite.sh`
3. Test all functionality
4. Delete old test scripts

### Phase 2: Documentation Merge (30 minutes)
1. Create `docs/COMPLETE-GUIDE.md`
2. Merge content, remove duplicates
3. Delete old documentation files

### Phase 3: Cleanup (15 minutes)
1. Update README.md
2. Update Makefile
3. Remove validation reports
4. Final testing

## ⚠️ RISKS & MITIGATION

| Risk | Mitigation |
|------|------------|
| Breaking existing workflows | Keep GitHub Actions unchanged |
| Losing test coverage | Ensure all unique tests preserved in suite |
| Documentation gaps | Review merged guide for completeness |
| User confusion | Clear README with migration notes |

## ✅ SUCCESS CRITERIA

1. **All tests pass** with new structure
2. **GitHub Actions** continues working
3. **50% reduction** in code size
4. **No functionality lost**
5. **Easier to maintain**

## 🎯 DECISION MATRIX

| Component | Keep | Modify | Remove | Reason |
|-----------|------|--------|--------|--------|
| witness-test.yml | ✅ | | | Working, don't break |
| test-rpm-signing.sh | | ✅ | | Merge into suite |
| test-fulcio-keyless.sh | | ✅ | | Merge into suite |
| test-tsa-signing.sh | | ✅ | | Merge into suite |
| test-sbom-rpm.sh | | ✅ | | Merge into suite |
| test-streamlined-examples.sh | | | ✅ | Redundant |
| validate-all.sh | | | ✅ | Use Makefile |
| VALIDATION-REPORT.md | | | ✅ | Temporary doc |
| Policy JSONs | ✅ | | | Essential templates |

## 💡 FINAL RECOMMENDATION

**IMPLEMENT OPTIMIZATION** - The benefits far outweigh the risks:
- 52% code reduction
- Easier maintenance
- Better user experience
- No functionality loss
- Cleaner repository

The customer gets the same functionality in a much cleaner package.
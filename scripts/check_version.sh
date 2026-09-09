#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Version & Documentation Synchronization Gate (cloud-native-observability)
# Guarantees that CHANGELOG.md, README.md, and release tags never drift out of sync.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

EXPECTED_VER="0.1.0"

CHANGELOG_VER=$(grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -n1 | sed -E 's/## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/')
README_HEADER_VER=$(grep -E '^# cloud-native-observability · v' README.md | head -n1 | sed -E 's/.*· v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

echo "========================================================"
echo "🔒 Verifying Version Synchronization (cloud-native-observability)"
echo "   - Expected Version: v$EXPECTED_VER"
echo "   - CHANGELOG.md:     v$CHANGELOG_VER"
echo "   - README.md Header: v$README_HEADER_VER"

if [ "$CHANGELOG_VER" != "$EXPECTED_VER" ]; then
  echo "❌ Error: CHANGELOG.md version (v$CHANGELOG_VER) does not match expected v$EXPECTED_VER"
  exit 1
fi

if [ "$README_HEADER_VER" != "$EXPECTED_VER" ]; then
  echo "❌ Error: README.md header version (v$README_HEADER_VER) does not match expected v$EXPECTED_VER"
  exit 1
fi

if [ "$CHANGELOG_VER" != "$README_HEADER_VER" ]; then
  echo "❌ Error: Version mismatch between CHANGELOG.md (v$CHANGELOG_VER) and README.md header (v$README_HEADER_VER)"
  exit 1
fi

# Genuine Git Tag verification
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  HEAD_TAG=$(git tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
  if [ -n "$HEAD_TAG" ]; then
    echo "   - Git Tag (HEAD):   $HEAD_TAG"
    if [ "$HEAD_TAG" != "v$EXPECTED_VER" ]; then
      echo "❌ Error: Git tag at HEAD ($HEAD_TAG) does not match expected v$EXPECTED_VER"
      exit 1
    fi
  else
    # In untagged development/CI pull request builds, report latest git release tag
    LATEST_TAG=$(git tag -l --sort=-v:refname "v*" 2>/dev/null | head -n1 || true)
    if [ -n "$LATEST_TAG" ]; then
      echo "   - Git Tag (latest): $LATEST_TAG"
    fi
  fi
fi

# CI Environment Tag check (e.g. tag push workflow)
if [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ -n "${GITHUB_REF_NAME:-}" ]; then
  echo "   - GitHub Ref Tag:   $GITHUB_REF_NAME"
  if [ "$GITHUB_REF_NAME" != "v$EXPECTED_VER" ]; then
    echo "❌ Error: GitHub Tag ref ($GITHUB_REF_NAME) does not match expected v$EXPECTED_VER"
    exit 1
  fi
fi

echo "========================================================"
echo "✅ All versions and documentation are strictly bound and synchronized!"

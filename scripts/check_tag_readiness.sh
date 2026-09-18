#!/usr/bin/env bash
set -euo pipefail

# Validates repository, documentation, and test state before creating or pushing a release tag.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

readonly SEMVER_PATTERN='[0-9]+\.[0-9]+\.[0-9]+'

fail() {
  printf '\033[0;31mERROR: %s\033[0m\n' "$*" >&2
  exit 1
}

tag="${1:-}"
if [[ -z "${tag}" ]]; then
  fail "Usage: $0 <vX.Y.Z>"
fi

if [[ ! "${tag}" =~ ^v${SEMVER_PATTERN}$ ]]; then
  fail "Tag must be valid SemVer prefixed with 'v' (e.g. v0.2.3): ${tag}"
fi

version="${tag#v}"

echo "========================================================"
echo "Checking release tag readiness for: ${tag}"
echo "========================================================"

# 1. Validates that the working tree is clean.
echo "-> Checking working tree status..."
if [[ -n "$(git status --porcelain)" ]]; then
  git status --short >&2
  fail "Working tree has uncommitted or untracked changes. Commit or stash them before releasing."
fi

# 2. Validates that CHANGELOG.md has an entry for this exact version as its top released section.
echo "-> Validating CHANGELOG.md top released version..."
top_changelog_version="$(grep -E "^## \[${SEMVER_PATTERN}\]" CHANGELOG.md | head -n1 | sed -E "s/^## \[(${SEMVER_PATTERN})\].*/\1/")"
if [[ "${top_changelog_version}" != "${version}" ]]; then
  fail "Top CHANGELOG.md release entry is v${top_changelog_version:-none}, but expected v${version}"
fi

# 3. Validates that README.md has this exact version.
echo "-> Validating README.md version references..."
readme_header="$(grep -E '^# cloud-native-observability · v' README.md | head -n1 | sed -E 's/.*· v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
if [[ "${readme_header}" != "${version}" ]]; then
  fail "README.md header version is v${readme_header:-none}, but expected v${version}"
fi

# 4. Runs GIT_TAG=$1 ./scripts/check_version.sh
echo "-> Running check_version.sh for ${tag}..."
GIT_TAG="${tag}" ./scripts/check_version.sh

# 5. Runs Promtool alert rules and unit tests
echo "-> Running Promtool alert test suites..."
bash ./scripts/test_alerts.sh

# 6. Runs Terraform formatting, validation, and TFLint
echo "-> Validating Terraform formatting, syntax, and TFLint..."
terraform -chdir=deploy/terraform fmt -check -recursive
terraform -chdir=deploy/terraform init -backend=false
terraform -chdir=deploy/terraform validate
(cd deploy/terraform && tflint --init && tflint --recursive)

echo "========================================================"
echo "✅ Release tag readiness check passed for ${tag}!"
echo "========================================================"

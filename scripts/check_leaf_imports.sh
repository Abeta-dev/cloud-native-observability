#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Zero-Dependency Standard-Library Isolation Gate (cloud-native-observability)
# Verifies that deploy/docker-compose/demo-app remains 100% pure Go standard
# library with zero external third-party dependencies.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEMO_DIR="${ROOT_DIR}/deploy/docker-compose/demo-app"

echo "========================================================"
echo "🌿 Verifying Zero-Dependency Standard-Library Isolation (demo-app)"

if [ ! -f "${DEMO_DIR}/go.mod" ]; then
  echo "❌ Error: ${DEMO_DIR}/go.mod not found"
  exit 1
fi

if grep -qE '^\s*require\b' "${DEMO_DIR}/go.mod"; then
  echo "❌ Error: ${DEMO_DIR}/go.mod contains external require directives:"
  grep -nE '^\s*require\b' "${DEMO_DIR}/go.mod"
  exit 1
fi

if [ -f "${DEMO_DIR}/go.sum" ] && [ -s "${DEMO_DIR}/go.sum" ]; then
  echo "❌ Error: ${DEMO_DIR}/go.sum exists and is non-empty (expected zero external dependencies)"
  exit 1
fi

EXTERNAL_DEPS=$(cd "${DEMO_DIR}" && go list -f '{{if not .Standard}}{{.ImportPath}}{{end}}' -deps ./... | grep -v '^github.com/abeta-dev/cloud-native-observability' || true)
if [ -n "${EXTERNAL_DEPS}" ]; then
  echo "❌ Error: demo-app imports non-stdlib external packages:"
  echo "${EXTERNAL_DEPS}"
  exit 1
fi

echo "✅ demo-app verified: 100% Go standard library (0 external dependencies)!"

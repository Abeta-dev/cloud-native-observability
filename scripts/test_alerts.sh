#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Promtool Unit Tests Runner for Prometheus Alerts
# Runs unit tests for Golden Signals, SLO Multi-Burn-Rate, and Kubernetes Node alerts.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

echo "=============================================================================="
echo "🧪 Running Prometheus Alert Rules Unit Tests via Promtool"
echo "=============================================================================="

# 1. Ensure rules extracted from Kubernetes PrometheusRule CRDs are up to date
python3 - <<'EOF'
import sys

def sync_crd_to_rules(crd_path, rules_path):
    with open(crd_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # Find spec:
    spec_idx = -1
    for i, line in enumerate(lines):
        if line.strip() == "spec:":
            spec_idx = i
            break
    
    if spec_idx == -1:
        print(f"Error: 'spec:' not found in {crd_path}")
        sys.exit(1)
    
    spec_lines = lines[spec_idx + 1:]
    # Remove leading 2 spaces
    rule_lines = []
    for line in spec_lines:
        if line.startswith("  "):
            rule_lines.append(line[2:])
        elif line.strip() == "":
            rule_lines.append(line)
        else:
            rule_lines.append(line)
    
    with open(rules_path, 'w', encoding='utf-8') as f:
        f.writelines(rule_lines)

sync_crd_to_rules("deploy/kubernetes/alerts/k8s-node-alerts.yaml", "deploy/kubernetes/alerts/rules/k8s-node-rules.yaml")
sync_crd_to_rules("deploy/kubernetes/alerts/slo-alerts.yaml", "deploy/kubernetes/alerts/rules/slo-rules.yaml")
print("✅ Synced Kubernetes PrometheusRule manifests with pure Prometheus rule definitions.")
EOF

TEST_FILES=(
  "deploy/kubernetes/alerts/tests/k8s-node-alerts-test.yaml"
  "deploy/kubernetes/alerts/tests/slo-alerts-test.yaml"
  "deploy/docker-compose/prometheus/alerts-test.yaml"
)

PROMTOOL_BIN="promtool"
if ! command -v promtool >/dev/null 2>&1; then
  if [ -x "/tmp/prometheus-2.51.0.darwin-arm64/promtool" ]; then
    PROMTOOL_BIN="/tmp/prometheus-2.51.0.darwin-arm64/promtool"
  fi
fi

if command -v "${PROMTOOL_BIN}" >/dev/null 2>&1 || [ -x "${PROMTOOL_BIN}" ]; then
  echo "Using promtool (${PROMTOOL_BIN})..."
  for tf in "${TEST_FILES[@]}"; do
    echo "Testing: ${tf}"
    "${PROMTOOL_BIN}" test rules "${tf}"
  done
elif command -v docker >/dev/null 2>&1; then
  echo "Using Docker promtool (prom/prometheus:v2.51.0)..."
  for tf in "${TEST_FILES[@]}"; do
    echo "Testing: ${tf}"
    docker run --rm -v "${ROOT_DIR}:/workspace" -w /workspace --entrypoint promtool prom/prometheus:v2.51.0 test rules "${tf}"
  done
else
  echo "❌ Error: Neither promtool nor docker is available to execute rule unit tests."
  exit 1
fi

echo "=============================================================================="
echo "✅ All Prometheus alert rules unit tests passed successfully!"
echo "=============================================================================="

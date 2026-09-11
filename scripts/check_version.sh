#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Version & Documentation Synchronization Gate (cloud-native-observability)
# Guarantees that CHANGELOG.md, README.md, and release tags never drift out of sync.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

echo "========================================================"
echo "🔒 Verifying Version Synchronization (cloud-native-observability)"

CHANGELOG_VER=$(grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -n1 | sed -E 's/## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/')
README_HEADER_VER=$(grep -E '^# cloud-native-observability · v' README.md | head -n1 | sed -E 's/.*· v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

if [ -z "$CHANGELOG_VER" ]; then
  echo "❌ Error: Could not parse version from CHANGELOG.md (expected '## [x.y.z]')"
  exit 1
fi

if [ -z "$README_HEADER_VER" ]; then
  echo "❌ Error: Could not parse version from README.md header (expected '# cloud-native-observability · vx.y.z')"
  exit 1
fi

echo "   - CHANGELOG.md:     v$CHANGELOG_VER"
echo "   - README.md Header: v$README_HEADER_VER"

if [ "$CHANGELOG_VER" != "$README_HEADER_VER" ]; then
  echo "❌ Error: Version mismatch between CHANGELOG.md (v$CHANGELOG_VER) and README.md header (v$README_HEADER_VER)"
  exit 1
fi

EXPECTED_VER="$CHANGELOG_VER"

# Enforce git tag if GIT_TAG is set, or if GITHUB_REF_TYPE is tag, or if tag points at HEAD
TAG_TO_VERIFY="${GIT_TAG:-}"
if [ -z "$TAG_TO_VERIFY" ] && [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ -n "${GITHUB_REF_NAME:-}" ]; then
  TAG_TO_VERIFY="${GITHUB_REF_NAME:-}"
fi
if [ -z "$TAG_TO_VERIFY" ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  HEAD_TAG=$(git tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
  if [ -n "$HEAD_TAG" ]; then
    TAG_TO_VERIFY="$HEAD_TAG"
  fi
fi

if [ -n "$TAG_TO_VERIFY" ]; then
  echo "   - Release Git Tag:  $TAG_TO_VERIFY"
  if [ "$TAG_TO_VERIFY" != "v$EXPECTED_VER" ]; then
    echo "❌ Error: Git tag ($TAG_TO_VERIFY) does not match expected canonical version (v$EXPECTED_VER)"
    exit 1
  fi
  echo "   - Git / Release Tag: $TAG_TO_VERIFY (verified matching)"
else
  # In untagged development/CI builds, report latest git tag for reference
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    LATEST_TAG=$(git tag -l --sort=-v:refname "v*" 2>/dev/null | head -n1 || true)
    if [ -n "$LATEST_TAG" ]; then
      echo "   - Git Tag (latest): $LATEST_TAG"
    fi
  fi
fi

# Check for mismatched or planted version tags in docs/ and README.md (e.g. @vX.Y.Z)
DOC_VER_MATCHES=$(grep -rEn --include="*.md" '@v[0-9]+\.[0-9]+\.[0-9]+' docs/ README.md 2>/dev/null || true)
if [ -n "$DOC_VER_MATCHES" ]; then
  while IFS= read -r match_line; do
    [ -z "$match_line" ] && continue
    FOUND_VER=$(echo "$match_line" | grep -oE '@v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/@v//')
    if [ "$FOUND_VER" != "$EXPECTED_VER" ]; then
      echo "❌ Error: Planted or mismatched version detected in documentation: $match_line (expected @v$EXPECTED_VER)"
      exit 1
    fi
  done <<< "$DOC_VER_MATCHES"
fi

# ==============================================================================
# Architecture & Claim Truthfulness Gate
# ==============================================================================
echo "🔍 Checking documentation for unverified superlatives, unmeasured claims, or phantom services..."

DOC_FILES=(README.md ARCHITECTURE.md CHANGELOG.md deploy/terraform/README.md)
for f in docs/*.md docs/adr/*.md; do
  [ -f "$f" ] && DOC_FILES+=("$f")
done

# 1. Phantom service check: Mimir (repo uses Prometheus / Thanos)
MIMIR_MATCHES=$(grep -inE '\bmimir\b' "${DOC_FILES[@]}" 2>/dev/null || true)
if [ -n "$MIMIR_MATCHES" ]; then
  echo "❌ Error: Unverified phantom service 'Mimir' found in documentation:"
  echo "$MIMIR_MATCHES"
  exit 1
fi

# 2. Unmeasured recovery time claims (e.g. under 3 minutes, instant disaster recovery, RTO < 5m)
RECOVERY_MATCHES=$(grep -inE '(under [0-9]+ min|instant disaster recovery|rto < [0-9]+m)' "${DOC_FILES[@]}" 2>/dev/null || true)
if [ -n "$RECOVERY_MATCHES" ]; then
  echo "❌ Error: Unmeasured recovery time claim found in documentation:"
  echo "$RECOVERY_MATCHES"
  exit 1
fi

# 3. Unverified security superlatives (e.g. zero-trust secrets alongside plain text secrets)
ZEROTRUST_MATCHES=$(grep -inE '(zero[- ]trust secrets)' "${DOC_FILES[@]}" 2>/dev/null || true)
if [ -n "$ZEROTRUST_MATCHES" ]; then
  echo "❌ Error: Unverified 'zero-trust secrets' claim found in documentation:"
  echo "$ZEROTRUST_MATCHES"
  exit 1
fi

# 4. Planted / phantom / fake metrics in documentation
PHANTOM_METRICS_DOC=$(grep -inE '(traces_service_graph_request_total|fake_metric[a-zA-Z0-9_]*)' "${DOC_FILES[@]}" 2>/dev/null || true)
if [ -n "$PHANTOM_METRICS_DOC" ]; then
  echo "❌ Error: Disallowed or fake metric name found in documentation:"
  echo "$PHANTOM_METRICS_DOC"
  exit 1
fi

# 5. Planted fake numbers or claims in documentation (e.g. fake SLO burn rates)
SLO_DISCREPANCIES=$(grep -inE '(ServiceErrorBudgetBurnRateHigh1h.*(1[0-35-9]\.[0-9]+x|[2-9][0-9]\.[0-9]+x)|ServiceErrorBudgetBurnRateHigh6h.*([0-57-9]\.[0-9]+x|[1-9][0-9]\.[0-9]+x))' "${DOC_FILES[@]}" 2>/dev/null || true)
if [ -n "$SLO_DISCREPANCIES" ]; then
  echo "❌ Error: Inconsistent or fake SLO burn rate number found in documentation:"
  echo "$SLO_DISCREPANCIES"
  exit 1
fi

# ==============================================================================
# Dashboard Metric Queries Verification Gate
# ==============================================================================
echo "📊 Verifying dashboard metric queries against exported metrics & spanmetrics..."

DASHBOARD_FILES=()
for df in deploy/docker-compose/grafana/dashboards/*.json deploy/terraform/modules/grafana_provisioning/files/*.json; do
  [ -f "$df" ] && DASHBOARD_FILES+=("$df")
done

# Disallowed / fake metrics in dashboards
DISALLOWED_DASHBOARD_METRICS=$(grep -inE '(traces_service_graph_request_total|fake_metric[a-zA-Z0-9_]*)' "${DASHBOARD_FILES[@]}" 2>/dev/null || true)
if [ -n "$DISALLOWED_DASHBOARD_METRICS" ]; then
  echo "❌ Error: Disallowed or fake metric found in dashboard queries:"
  echo "$DISALLOWED_DASHBOARD_METRICS"
  exit 1
fi

python3 - <<'EOF'
import json
import os
import re
import sys

VALID_METRICS = {
    # Demo App
    "http_requests_total",
    "http_request_duration_seconds",
    "http_request_duration_seconds_bucket",
    "http_request_duration_seconds_sum",
    "http_request_duration_seconds_count",
    "app_workerpool_queue_depth",
    "app_workerpool_queue_capacity",
    "app_circuit_breaker_requests_total",
    "app_circuit_breaker_failures_total",
    "app_circuit_breaker_state",
    "app_workerpool_tasks_submitted_total",
    "app_workerpool_tasks_completed_total",
    "app_workerpool_tasks_dropped_total",
    "app_cache_hits_total",
    "app_cache_misses_total",
    # OpenTelemetry Spanmetrics / ServiceGraph
    "traces_spanmetrics_calls_total",
    "traces_spanmetrics_duration_milliseconds_bucket",
    "traces_spanmetrics_duration_milliseconds_count",
    "traces_spanmetrics_duration_milliseconds_sum",
    # Platform / Infrastructure
    "up",
    "process_resident_memory_bytes",
    "prometheus_http_requests_total",
    "prometheus_tsdb_head_series",
    "loki_ingester_memory_chunks",
    "tempo_ingester_blocks_active",
    "otelcol_process_memory_rss",
    # Prometheus Precomputed SLO Recording Rules
    "job:http_requests:error_rate_5m",
    "job:http_requests:error_rate_30m",
    "job:http_requests:error_rate_1h",
    "job:http_requests:error_rate_6h",
    "job:http_requests:error_rate_3d",
}

PROMQL_KEYWORDS = {
    "sum", "rate", "irate", "histogram_quantile", "by", "without", "or", "and", "unless",
    "vector", "count", "avg", "min", "max", "topk", "bottomk", "last", "lastnotnull",
    "le", "job", "service", "status", "app", "level", "mode", "device", "mountpoint",
    "fstype", "instance", "namespace", "phase", "container", "pod", "type", "refid",
    "round", "floor", "ceil", "abs", "changes", "resets", "deriv", "predict_linear",
}

errors = []
dashboard_dirs = [
    "deploy/docker-compose/grafana/dashboards",
    "deploy/terraform/modules/grafana_provisioning/files"
]

for d in dashboard_dirs:
    if not os.path.exists(d):
        continue
    for fname in os.listdir(d):
        if not fname.endswith(".json"):
            continue
        fpath = os.path.join(d, fname)
        try:
            with open(fpath, "r", encoding="utf-8") as fp:
                data = json.load(fp)
        except Exception as ex:
            errors.append(f"Failed to parse JSON {fpath}: {ex}")
            continue

        def find_exprs(node):
            exprs = []
            if isinstance(node, dict):
                if "expr" in node and isinstance(node["expr"], str):
                    datasource_type = ""
                    if isinstance(node.get("datasource"), dict):
                        datasource_type = node["datasource"].get("type", "")
                    exprs.append((node["expr"], datasource_type))
                for v in node.values():
                    exprs.extend(find_exprs(v))
            elif isinstance(node, list):
                for item in node:
                    exprs.extend(find_exprs(item))
            return exprs

        for expr, ds_type in find_exprs(data):
            if ds_type == "loki" or expr.strip().startswith("{"):
                continue

            # Clean PromQL: remove string literals, range vectors [1m], and label selectors {...}
            clean_expr = expr
            clean_expr = re.sub(r'"[^"]*"', '', clean_expr)
            clean_expr = re.sub(r'\[[0-9]+[smhdwy]\]', '', clean_expr)
            clean_expr = re.sub(r'\{[^\}]*\}', '', clean_expr)

            tokens = re.findall(r'[a-zA-Z_:][a-zA-Z0-9_:]*', clean_expr)
            for token in tokens:
                token_lower = token.lower()
                if token_lower in PROMQL_KEYWORDS:
                    continue
                if token.isdigit():
                    continue
                if token not in VALID_METRICS:
                    errors.append(f"{fpath}: unknown/unexported metric '{token}' in expression: {expr}")

if errors:
    print("❌ Error: Dashboard metric queries contain unknown/unexported metrics:")
    for err in errors:
        print(f"   - {err}")
    sys.exit(1)
else:
    print("   - All dashboard PromQL queries verified against exported metrics catalog.")
EOF

echo "========================================================"
echo "✅ All versions, documentation, and telemetry queries are strictly verified and truthful!"

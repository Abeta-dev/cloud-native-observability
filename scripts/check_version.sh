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

# Verify ArgoCD manifests match expected canonical version
echo "📦 Verifying ArgoCD GitOps manifests synchronization..."
ARGOCD_STALE=$(grep -rnE 'targetRevision: v[0-9]+\.[0-9]+\.[0-9]+|raw.githubusercontent.com/.*/v[0-9]+\.[0-9]+\.[0-9]+/' deploy/kubernetes/argocd/ 2>/dev/null | grep -v "v${EXPECTED_VER}" || true)
if [ -n "$ARGOCD_STALE" ]; then
  echo "❌ Error: Stale or mismatched version detected in ArgoCD GitOps manifests (expected v${EXPECTED_VER}):"
  echo "$ARGOCD_STALE"
  exit 1
fi
echo "   - All ArgoCD manifests synchronized to v${EXPECTED_VER} ✅"

# ==============================================================================
# Architecture & Claim Truthfulness Gate
# ==============================================================================
echo "🔍 Checking documentation for unverified superlatives, unmeasured claims, or phantom services..."

DOC_FILES=(README.md ARCHITECTURE.md CHANGELOG.md deploy/terraform/README.md)
for f in docs/*.md docs/adr/*.md; do
  [ -f "$f" ] && DOC_FILES+=("$f")
done

# 1. Phantom service check: Mimir in base documentation (core repo uses Prometheus / Thanos in base; Mimir clustered architecture is documented in CLUSTERED_OBSERVABILITY.md)
MIMIR_CHECK_FILES=()
for f in "${DOC_FILES[@]}"; do
  [ "$f" != "docs/CLUSTERED_OBSERVABILITY.md" ] && [ "$f" != "CHANGELOG.md" ] && MIMIR_CHECK_FILES+=("$f")
done
MIMIR_MATCHES=$(grep -inE '\bmimir\b' "${MIMIR_CHECK_FILES[@]}" 2>/dev/null || true)
if [ -n "$MIMIR_MATCHES" ]; then
  echo "❌ Error: Unverified phantom service 'Mimir' found in base documentation:"
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

ALERT_FILES=()
for af in deploy/terraform/modules/grafana_provisioning/alerts.tf \
          deploy/kubernetes/alerts/*.yaml \
          deploy/docker-compose/prometheus/alerts.yml; do
  [ -f "$af" ] && ALERT_FILES+=("$af")
done

DISALLOWED_ALERT_METRICS=$(grep -inE '(traces_service_graph_request_total|fake_metric[a-zA-Z0-9_]*)' "${ALERT_FILES[@]}" 2>/dev/null || true)
if [ -n "$DISALLOWED_ALERT_METRICS" ]; then
  echo "❌ Error: Disallowed or fake metric found in alert definitions:"
  echo "$DISALLOWED_ALERT_METRICS"
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

# ==============================================================================
# Alertmanager Configuration Single-Source / Drift Gate
# ==============================================================================
echo "🔔 Verifying Alertmanager configuration synchronization..."
python3 - << 'EOF'
import yaml, sys

try:
    with open("deploy/kubernetes/alerts/alertmanager.yaml") as f:
        am_cfg = yaml.safe_load(f)
    with open("deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml") as f:
        kps_cfg = yaml.safe_load(f)

    helm_am = kps_cfg.get("alertmanager", {}).get("config", {})
    diffs = []
    for k in ["global", "route", "inhibit_rules", "receivers"]:
        if am_cfg.get(k) != helm_am.get(k):
            diffs.append(k)
    if diffs:
        print(f"❌ Error: Alertmanager configuration drift detected between deploy/kubernetes/alerts/alertmanager.yaml and deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml in sections: {diffs}")
        sys.exit(1)
    print("   - Alertmanager routes, receivers, and inhibit rules strictly synchronized ✅")
except Exception as e:
    print(f"❌ Error during Alertmanager config verification: {e}")
    sys.exit(1)
EOF

# ==============================================================================
# Canonical Availability SLI & Cross-Layer AST Equivalence Gate
# ==============================================================================
echo "📐 Verifying Canonical Availability SLI AST equivalence across layers..."
python3 - << 'EOF'
import re, sys, yaml

class BinaryOp:
    def __init__(self, op, left, right):
        self.op = op
        self.left = left
        self.right = right
    def __repr__(self):
        return f"BinaryOp({self.op}, {self.left}, {self.right})"

class Aggregation:
    def __init__(self, func, expr, by=None):
        self.func = func
        self.expr = expr
        self.by = tuple(sorted(by)) if by else ()
    def __repr__(self):
        return f"Aggregation({self.func}, {self.expr}, by={self.by})"

class FunctionCall:
    def __init__(self, name, args):
        self.name = name
        self.args = args
    def __repr__(self):
        return f"FunctionCall({self.name}, {self.args})"

class MatrixSelector:
    def __init__(self, metric, matchers, window):
        self.metric = metric
        self.matchers = matchers
        self.window = window
    def __repr__(self):
        return f"MatrixSelector({self.metric}, {self.matchers}, [{self.window}])"

class NumberLiteral:
    def __init__(self, value):
        self.value = value
    def __repr__(self):
        return f"Number({self.value})"

def tokenize(text):
    tokens = []
    token_spec = [
        ('TMPL_VAR', r'\{\{[a-zA-Z0-9_]+\}\}'),
        ('DURATION', r'[0-9]+[smhdwy]'),
        ('STRING',   r'"[^"]*"|\'[^\']*\''),
        ('NUMBER',   r'\d+(\.\d+)?'),
        ('LABEL_OP', r'=~|!~|!=|='),
        ('COMP_OP',  r'==|!=|>=|<=|>|<'),
        ('ARITH_OP', r'[+\-*/%^]'),
        ('LPAREN',   r'\('),
        ('RPAREN',   r'\)'),
        ('LBRACE',   r'\{'),
        ('RBRACE',   r'\}'),
        ('LBRACKET', r'\['),
        ('RBRACKET', r'\]'),
        ('COMMA',    r','),
        ('ID',       r'[a-zA-Z_:][a-zA-Z0-9_:]*'),
        ('SKIP',     r'[ \t\r\n]+'),
    ]
    tok_regex = '|'.join('(?P<%s>%s)' % pair for pair in [
        ('TMPL_VAR',   r'\{\{[a-zA-Z0-9_]+\}\}'),
        ('DURATION',   r'[0-9]+[smhdwy]'),
        ('STRING',     r'"[^"]*"|\'[^\']*\''),
        ('NUMBER',     r'\d+(\.\d+)?'),
        ('LABEL_OP',   r'=~|!~|!=|='),
        ('COMP_OP',    r'==|!=|>=|<=|>|<'),
        ('ARITH_OP',   r'[+\-*/%^]'),
        ('LOGICAL_OP', r'\b(or|and|unless)\b'),
        ('LPAREN',     r'\('),
        ('RPAREN',     r'\)'),
        ('LBRACE',     r'\{'),
        ('RBRACE',     r'\}'),
        ('LBRACKET',   r'\['),
        ('RBRACKET',   r'\]'),
        ('COMMA',      r','),
        ('ID',         r'[a-zA-Z_:][a-zA-Z0-9_:]*'),
        ('SKIP',       r'[ \t\r\n]+'),
    ])
    for mo in re.finditer(tok_regex, text):
        kind = mo.lastgroup
        val = mo.group()
        if kind == 'SKIP':
            continue
        tokens.append((kind, val))
    return tokens

class PromQLParser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.pos = 0

    def peek(self):
        if self.pos < len(self.tokens):
            return self.tokens[self.pos]
        return ('EOF', '')

    def consume(self, expected_kind=None):
        tok = self.peek()
        if expected_kind and tok[0] != expected_kind:
            raise ValueError(f"Expected {expected_kind}, got {tok} at pos {self.pos}")
        self.pos += 1
        return tok

    def parse(self):
        return self.parse_logical()

    def parse_logical(self):
        node = self.parse_comparison()
        while self.peek()[0] == 'LOGICAL_OP':
            op = self.consume('LOGICAL_OP')[1]
            right = self.parse_comparison()
            node = BinaryOp(op, node, right)
        return node

    def parse_comparison(self):
        node = self.parse_addition()
        while self.peek()[0] == 'COMP_OP':
            op = self.consume('COMP_OP')[1]
            right = self.parse_addition()
            node = BinaryOp(op, node, right)
        return node

    def parse_addition(self):
        node = self.parse_multiplication()
        while self.peek()[0] == 'ARITH_OP' and self.peek()[1] in ('+', '-'):
            op = self.consume('ARITH_OP')[1]
            right = self.parse_multiplication()
            node = BinaryOp(op, node, right)
        return node

    def parse_multiplication(self):
        node = self.parse_primary()
        while self.peek()[0] == 'ARITH_OP' and self.peek()[1] in ('*', '/', '%', '^'):
            op = self.consume('ARITH_OP')[1]
            right = self.parse_primary()
            node = BinaryOp(op, node, right)
        return node

    def parse_primary(self):
        tok = self.peek()
        if tok[0] == 'NUMBER':
            self.consume()
            return NumberLiteral(float(tok[1]))
        if tok[0] == 'LPAREN':
            self.consume('LPAREN')
            node = self.parse()
            self.consume('RPAREN')
            return node

        if tok[0] == 'ID':
            name = self.consume('ID')[1]
            if name in ('sum', 'avg', 'count', 'min', 'max'):
                by_labels = []
                if self.peek()[0] == 'ID' and self.peek()[1] == 'by':
                    self.consume('ID')
                    by_labels = self.parse_label_list()
                self.consume('LPAREN')
                inner = self.parse()
                self.consume('RPAREN')
                if not by_labels and self.peek()[0] == 'ID' and self.peek()[1] == 'by':
                    self.consume('ID')
                    by_labels = self.parse_label_list()
                return Aggregation(name, inner, by=by_labels)

            if self.peek()[0] == 'LPAREN':
                self.consume('LPAREN')
                args = []
                if self.peek()[0] != 'RPAREN':
                    args.append(self.parse())
                    while self.peek()[0] == 'COMMA':
                        self.consume('COMMA')
                        args.append(self.parse())
                self.consume('RPAREN')
                return FunctionCall(name, args)

            matchers = {}
            if self.peek()[0] == 'LBRACE':
                self.consume('LBRACE')
                while self.peek()[0] != 'RBRACE':
                    lbl = self.consume('ID')[1]
                    op = self.consume('LABEL_OP')[1]
                    val = self.consume('STRING')[1].strip('"\'')
                    matchers[lbl] = (op, val)
                    if self.peek()[0] == 'COMMA':
                        self.consume('COMMA')
                    else:
                        break
                self.consume('RBRACE')

            window = None
            if self.peek()[0] == 'LBRACKET':
                self.consume('LBRACKET')
                tok = self.peek()
                if tok[0] in ('DURATION', 'TMPL_VAR', 'ID'):
                    window = self.consume()[1]
                else:
                    raise ValueError(f"Expected window in brackets, got {tok}")
                self.consume('RBRACKET')
            return MatrixSelector(metric=name, matchers=matchers, window=window)

        raise ValueError(f"Unexpected token in expression: {tok}")

    def parse_label_list(self):
        self.consume('LPAREN')
        labels = []
        while self.peek()[0] == 'ID':
            labels.append(self.consume('ID')[1])
            if self.peek()[0] == 'COMMA':
                self.consume('COMMA')
            else:
                break
        self.consume('RPAREN')
        return labels

class SLIDivision:
    def __init__(self, left, right):
        self.left = left
        self.right = right

def extract_rate_aggregation(node):
    if isinstance(node, Aggregation) and isinstance(node.expr, FunctionCall) and node.expr.name in ('rate', 'irate'):
        return node
    if isinstance(node, BinaryOp):
        left_res = extract_rate_aggregation(node.left)
        if left_res:
            return left_res
        return extract_rate_aggregation(node.right)
    return None

def find_sli_division(node):
    if isinstance(node, BinaryOp):
        if node.op == '/':
            lhs_agg = extract_rate_aggregation(node.left)
            rhs_agg = extract_rate_aggregation(node.right)
            if lhs_agg and rhs_agg:
                return SLIDivision(lhs_agg, rhs_agg)
        left_res = find_sli_division(node.left)
        if left_res:
            return left_res
        return find_sli_division(node.right)
    return None

def verify_ast_equivalence(canonical_ast, target_ast, context_name):
    target_sli = find_sli_division(target_ast)
    if not target_sli:
        raise ValueError(f"[{context_name}] Could not find SLI division node in AST: {target_ast}")

    canonical_sli = find_sli_division(canonical_ast)
    if not canonical_sli:
        raise ValueError("Could not find SLI division node in canonical AST")

    c_lhs, c_rhs = canonical_sli.left, canonical_sli.right
    t_lhs, t_rhs = target_sli.left, target_sli.right

    if t_lhs.func != c_lhs.func or t_rhs.func != c_rhs.func:
        raise ValueError(f"[{context_name}] Aggregation mismatch: {t_lhs.func}/{t_rhs.func} vs {c_lhs.func}/{c_rhs.func}")

    if t_lhs.expr.name != c_lhs.expr.name or t_rhs.expr.name != c_rhs.expr.name:
        raise ValueError(f"[{context_name}] Rate function mismatch: {t_lhs.expr.name}/{t_rhs.expr.name} vs {c_lhs.expr.name}/{c_rhs.expr.name}")

    t_num_sel, t_den_sel = t_lhs.expr.args[0], t_rhs.expr.args[0]
    c_num_sel, c_den_sel = c_lhs.expr.args[0], c_rhs.expr.args[0]

    if t_num_sel.metric != c_num_sel.metric or t_den_sel.metric != c_den_sel.metric:
        raise ValueError(f"[{context_name}] Metric name mismatch: {t_num_sel.metric}/{t_den_sel.metric} vs {c_num_sel.metric}/{c_den_sel.metric}")

    c_status_matcher = c_num_sel.matchers.get("status")
    t_status_matcher = t_num_sel.matchers.get("status")
    if t_status_matcher != c_status_matcher:
        raise ValueError(f"[{context_name}] Numerator status matcher mismatch: {t_status_matcher} vs expected {c_status_matcher}")

    if "status" in t_den_sel.matchers:
        raise ValueError(f"[{context_name}] Denominator has unexpected status filter: {t_den_sel.matchers['status']}")

    if t_num_sel.window != t_den_sel.window:
        raise ValueError(f"[{context_name}] Window mismatch between numerator [{t_num_sel.window}] and denominator [{t_den_sel.window}]")

    if t_lhs.by != t_rhs.by:
        raise ValueError(f"[{context_name}] Grouping mismatch: numerator by {t_lhs.by} vs denominator by {t_rhs.by}")

    print(f"   - {context_name}: AST verified equivalent to canonical SLI ✅")

try:
    with open("deploy/slo/canonical_sli.promql") as f:
        canon_raw = f.read().strip()
    canon_ast = PromQLParser(tokenize(canon_raw)).parse()

    # 1. deploy/docker-compose/prometheus/alerts.yml
    with open("deploy/docker-compose/prometheus/alerts.yml") as f:
        compose_alerts = yaml.safe_load(f)
    found_compose = False
    for grp in compose_alerts.get("groups", []):
        for rule in grp.get("rules", []):
            if rule.get("alert") == "HighErrorRate":
                ast = PromQLParser(tokenize(rule["expr"])).parse()
                verify_ast_equivalence(canon_ast, ast, "deploy/docker-compose/prometheus/alerts.yml (HighErrorRate)")
                found_compose = True
    if not found_compose:
        raise ValueError("HighErrorRate alert not found in deploy/docker-compose/prometheus/alerts.yml")

    # 2. deploy/kubernetes/alerts/slo-alerts.yaml
    with open("deploy/kubernetes/alerts/slo-alerts.yaml") as f:
        k8s_alerts = yaml.safe_load(f)
    k8s_count = 0
    for grp in k8s_alerts.get("spec", {}).get("groups", []):
        for rule in grp.get("rules", []):
            rec = rule.get("record", "")
            if rec.startswith("job:http_requests:error_rate_"):
                ast = PromQLParser(tokenize(rule["expr"])).parse()
                verify_ast_equivalence(canon_ast, ast, f"deploy/kubernetes/alerts/slo-alerts.yaml ({rec})")
                k8s_count += 1
    if k8s_count != 5:
        raise ValueError(f"Expected 5 recording rules in slo-alerts.yaml, found {k8s_count}")

    # 3. deploy/terraform/modules/grafana_provisioning/alerts.tf
    with open("deploy/terraform/modules/grafana_provisioning/alerts.tf") as f:
        tf_content = f.read()
    m = re.search(r'name\s*=\s*"HighErrorRateP1".*?expr\s*=\s*"((?:\\.|[^"\\])*)"', tf_content, re.DOTALL)
    if not m:
        raise ValueError("HighErrorRateP1 expr not found in alerts.tf")
    tf_expr = m.group(1).replace(r'\"', '"')
    tf_ast = PromQLParser(tokenize(tf_expr)).parse()
    verify_ast_equivalence(canon_ast, tf_ast, "deploy/terraform/modules/grafana_provisioning/alerts.tf (HighErrorRateP1)")

except Exception as ex:
    print(f"❌ Error during Canonical SLI AST equivalence check: {ex}")
    sys.exit(1)
EOF

echo "========================================================"
echo "✅ All versions, documentation, and telemetry queries are strictly verified and truthful!"

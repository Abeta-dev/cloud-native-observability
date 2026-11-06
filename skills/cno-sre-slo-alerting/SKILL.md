---
name: cno-sre-slo-alerting
description: Google SRE multi-window multi-burn-rate SLO alerting, Prometheus recording rules, Alertmanager routing parity, and PromQL AST equivalence gates for github.com/abeta-dev/cloud-native-observability (v0.3.0).
---

# `cno-sre-slo-alerting` Subskill (`v0.3.0`)

Key configuration paths:
- `deploy/slo/canonical_sli.promql`
- `deploy/kubernetes/alerts/slo-alerts.yaml` & `deploy/kubernetes/alerts/k8s-node-alerts.yaml`
- `deploy/kubernetes/alerts/alertmanager.yaml`
- `deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml`
- `deploy/docker-compose/prometheus/alerts.yml`
- `deploy/terraform/modules/grafana_provisioning/alerts.tf`

## 1. Canonical HTTP Availability SLI & Recording Rules

All layers of the repository compute the HTTP 5xx error ratio using the canonical formula in `deploy/slo/canonical_sli.promql`:

```promql
(sum(rate(http_requests_total{status=~"5.."}[{{WINDOW}}])) or vector(0)) / (sum(rate(http_requests_total[{{WINDOW}}])) > 0) or vector(0)
```

Pre-computed recording rules in `deploy/kubernetes/alerts/slo-alerts.yaml` evaluate this ratio across all required SRE windows:
- `job:http_requests:error_rate_5m`
- `job:http_requests:error_rate_30m`
- `job:http_requests:error_rate_1h`
- `job:http_requests:error_rate_6h`
- `job:http_requests:error_rate_3d`

> **Truth Gate Warning**: `./scripts/check_version.sh` parses the PromQL AST across `deploy/slo/canonical_sli.promql`, `deploy/docker-compose/prometheus/alerts.yml`, `deploy/kubernetes/alerts/slo-alerts.yaml`, and `deploy/terraform/modules/grafana_provisioning/alerts.tf`. Do not alter label matchers or aggregation operators in one file without updating all layers.

## 2. Google SRE Multi-Window Multi-Burn-Rate Alert Tiers (`99.9%` SLO, `0.001` Error Budget)

| Alert | Short Window | Long Window | Burn Rate | Threshold (`Burn * 0.001`) | Severity | Action |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `ServiceErrorBudgetBurnRateHigh1h` | `5m` | `1h` | `14.4x` | `> 0.0144` | `critical` | PagerDuty / immediate wake-up (2% budget burned in 1h) |
| `ServiceErrorBudgetBurnRateHigh6h` | `30m` | `6h` | `6.0x` | `> 0.006` | `critical` | PagerDuty / urgent response (5% budget burned in 6h) |
| `ServiceErrorBudgetBurnRateSlow3d` | `6h` | `3d` | `1.0x` | `> 0.001` | `warning` | Slack / Jira ticket (10% budget burned in 3d) |

Both the short-window and long-window expressions MUST exceed the threshold simultaneously (`and`) so alerts reset rapidly once an incident is mitigated.

## 3. Alertmanager Standalone vs. Helm Values Parity

Whenever you modify routing trees, inhibit rules, or receivers in `deploy/kubernetes/alerts/alertmanager.yaml`, you **must** mirror the exact same YAML structure inside `alertmanager.config` in `deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml`. Verify parity with `./scripts/check_version.sh` and run Promtool alert tests via `./scripts/test_alerts.sh`.

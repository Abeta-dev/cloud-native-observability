---
name: cno-sre-slo-alerting
description: Google SRE multi-window multi-burn-rate SLO alerting, Prometheus recording rules, Alertmanager routing parity, and PromQL AST equivalence gates for github.com/Abeta-dev/cloud-native-observability (v0.2.5).
---

# `cno-sre-slo-alerting` Subskill (`v0.2.5`)

Key configuration paths:
- `configs/prometheus/rules/recording_rules.yml`
- `configs/prometheus/rules/slo_alerts.yml`
- `configs/alertmanager/alertmanager.yml`
- `deploy/kubernetes/base/alertmanager/configmap.yaml`
- `deploy/terraform/alerts.tf`

## 1. Canonical HTTP Availability SLI & Recording Rules

All layers of the repository compute the HTTP 5xx error ratio using the canonical formula:

```promql
sum by (job) (rate(http_requests_total{status=~"5.."}[WINDOW]))
/
sum by (job) (rate(http_requests_total[WINDOW]))
```

Pre-computed recording rules in `configs/prometheus/rules/recording_rules.yml` evaluate this ratio across all required SRE windows:
- `job:http_requests:error_rate_5m`
- `job:http_requests:error_rate_30m`
- `job:http_requests:error_rate_1h`
- `job:http_requests:error_rate_6h`
- `job:http_requests:error_rate_3d`

> **Truth Gate Warning**: `./scripts/check_version.sh` parses the PromQL AST across `recording_rules.yml`, `service-golden-signals.json`, and `deploy/terraform/alerts.tf`. Do not alter label matchers or aggregation operators in one file without updating all three.

## 2. Google SRE Multi-Window Multi-Burn-Rate Alert Tiers (`99.9%` SLO, `0.001` Error Budget)

| Tier | Short Window | Long Window | Burn Rate | Threshold (`Burn * 0.001`) | Severity | Action |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Page (Fast Burn)** | `5m` | `1h` | `14.4x` | `> 0.0144` | `critical` | PagerDuty / immediate wake-up (2% budget burned in 1h) |
| **Page (Medium Burn)** | `30m` | `6h` | `6.0x` | `> 0.006` | `critical` | PagerDuty / urgent response (5% budget burned in 6h) |
| **Ticket (Slow Burn)** | `6h` | `3d` | `1.0x` | `> 0.001` | `warning` | Slack / Jira ticket (10% budget burned in 3d) |

Both the short-window and long-window expressions MUST exceed the threshold simultaneously (`and`) so alerts reset rapidly once an incident is mitigated.

## 3. Alertmanager Local vs. Kubernetes ConfigMap Parity

Whenever you modify routing trees, inhibit rules, or receivers in `configs/alertmanager/alertmanager.yml`, you **must** mirror the exact same YAML structure inside the `alertmanager.yml: |` data block of `deploy/kubernetes/base/alertmanager/configmap.yaml`. Verify parity with `./scripts/check_version.sh`.

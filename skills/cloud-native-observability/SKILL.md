---
name: cloud-native-observability
description: Umbrella router and operational blueprint for github.com/Abeta-dev/cloud-native-observability (v0.3.0). Use when instrumenting Go services with OpenTelemetry, configuring OTel Collector + Prometheus + Grafana + Loki + Tempo, authoring Google SRE burn-rate SLO alerts, or deploying via ArgoCD and Terraform.
---

# `cloud-native-observability` Umbrella Skill (`v0.3.0`)

Repository: `github.com/Abeta-dev/cloud-native-observability` (`v0.3.0`, `Go 1.26.0`)

## When to Use

- Instrumenting Go services (built with `go-libs` and `go-app-kit`) to emit correlated OpenTelemetry traces, metrics, and structured JSON logs (`docs/INTEGRATION_GUIDE.md`)
- Operating or modifying the local Docker Compose LGTM stack (`compose.yaml`, `deploy/docker-compose/docker-compose.yml`) or Kubernetes Helm/ArgoCD deployments (`deploy/kubernetes/`)
- Authoring or auditing Prometheus recording rules, Google SRE multi-window burn-rate alerts, or Grafana dashboards
- Validating cross-layer observability parity via `./scripts/check_version.sh` and `./scripts/test_alerts.sh`

## Subskill Routing

| Domain | Subskill | Key Files & Components |
| :--- | :--- | :--- |
| **OTel Collector & LGTM Telemetry Pipeline** | [`cno-otel-lgtm-stack`](../cno-otel-lgtm-stack/SKILL.md) | `deploy/docker-compose/otel-collector/otel-collector-config.yml`, `deploy/docker-compose/prometheus/prometheus.yml`, `deploy/docker-compose/loki/loki-config.yml`, `deploy/docker-compose/tempo/tempo-config.yml`, `deploy/docker-compose/grafana/` |
| **Google SRE Multi-Window Burn-Rate Alerting** | [`cno-sre-slo-alerting`](../cno-sre-slo-alerting/SKILL.md) | `deploy/slo/canonical_sli.promql`, `deploy/kubernetes/alerts/slo-alerts.yaml`, `deploy/kubernetes/alerts/k8s-node-alerts.yaml`, `deploy/kubernetes/alerts/alertmanager.yaml`, `deploy/docker-compose/prometheus/alerts.yml` |
| **Kubernetes GitOps (ArgoCD) & Terraform IaC** | [`cno-gitops-terraform`](../cno-gitops-terraform/SKILL.md) | `deploy/kubernetes/helm/`, `deploy/kubernetes/examples/overlays/`, `deploy/kubernetes/argocd/`, `deploy/terraform/` |

## Core Architectural Invariants

1. **Vendor-Neutral OTLP Ingestion**: Applications send OTLP traces and logs to the OpenTelemetry Collector (`4317` gRPC / `4318` HTTP) — never directly to downstream trace/log storage backends.
2. **Three-Pillar Correlation**:
   - **Metrics → Traces**: Prometheus scrapes `/metrics` and OpenTelemetry Collector spanmetrics on `:8889`, linked to Tempo in Grafana (`deploy/docker-compose/grafana/provisioning/datasources/datasources.yml`).
   - **Logs → Traces**: Structured `slog` JSON logs include `trace_id` and `span_id`, indexed as Loki TSDB `v13` structured metadata (`deploy/docker-compose/loki/loki-config.yml`).
   - **Traces → Metrics**: The OpenTelemetry Collector `spanmetrics` connector synthesizes RED metrics (`traces_spanmetrics_calls_total`, `traces_spanmetrics_duration_milliseconds_bucket`) from spans and exposes them on `:8889` for Prometheus scraping.
3. **Config Parity Enforcement**: Always run `./scripts/check_version.sh`, `./scripts/test_alerts.sh`, and `(cd deploy/docker-compose/demo-app && go test -race -cover ./...)` after editing any Go, YAML, JSON, or `.tf` configuration file.

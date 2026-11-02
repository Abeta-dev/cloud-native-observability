---
name: cloud-native-observability
description: Umbrella router and operational blueprint for github.com/Abeta-dev/cloud-native-observability (v0.2.4). Use when instrumenting Go services with OpenTelemetry, configuring OTel Collector + Prometheus + Grafana + Loki + Tempo, authoring Google SRE burn-rate SLO alerts, or deploying via ArgoCD and Terraform.
---

# `cloud-native-observability` Umbrella Skill (`v0.2.4`)

Repository: `github.com/Abeta-dev/cloud-native-observability` (`v0.2.4`, `Go 1.26.0`)

## When to Use

- Instrumenting Go services (built with `go-libs` and `go-app-kit`) to emit correlated OpenTelemetry traces, metrics, and structured JSON logs
- Operating or modifying the local Docker Compose LGTM stack (`docker-compose.yml`) or Kubernetes Kustomize deployments (`deploy/kubernetes/`)
- Authoring or auditing Prometheus recording rules, Google SRE multi-window burn-rate alerts, or Grafana dashboards
- Validating cross-layer observability parity via `./scripts/check_version.sh` and `tests/config_validation_test.go`

## Subskill Routing

| Domain | Subskill | Key Files & Components |
| :--- | :--- | :--- |
| **OTel Collector & LGTM Telemetry Pipeline** | [`cno-otel-lgtm-stack`](../cno-otel-lgtm-stack/SKILL.md) | `configs/otel-collector/`, `configs/prometheus/`, `configs/loki/`, `configs/tempo/`, `configs/grafana/` |
| **Google SRE Multi-Window Burn-Rate Alerting** | [`cno-sre-slo-alerting`](../cno-sre-slo-alerting/SKILL.md) | `configs/prometheus/rules/recording_rules.yml`, `configs/prometheus/rules/slo_alerts.yml`, `configs/alertmanager/` |
| **Kubernetes GitOps (ArgoCD) & Terraform IaC** | [`cno-gitops-terraform`](../cno-gitops-terraform/SKILL.md) | `deploy/kubernetes/base/`, `deploy/kubernetes/overlays/`, `deploy/kubernetes/argocd/`, `deploy/terraform/` |

## Core Architectural Invariants

1. **Vendor-Neutral OTLP Ingestion**: Applications send all telemetry exclusively to the OpenTelemetry Collector (`4317` gRPC / `4318` HTTP) — never directly to downstream storage backends.
2. **Three-Pillar Correlation**:
   - **Metrics → Traces**: Prometheus histograms carry OpenTelemetry trace exemplars (`--enable-feature=exemplar-storage`).
   - **Logs → Traces**: Structured `slog` JSON logs include `trace_id` and `span_id`, extracted by the OTel Collector `transform` processor into Loki TSDB `v13` structured metadata.
   - **Traces → Metrics**: Tempo's `metrics_generator` remote-writes RED (`traces_spanmetrics_calls_total`, `traces_spanmetrics_latency_bucket`) metrics to Prometheus.
3. **Config Parity Enforcement**: Always run `./scripts/check_version.sh` and `go test -v ./tests/...` after editing any YAML, JSON, or `.tf` configuration file.

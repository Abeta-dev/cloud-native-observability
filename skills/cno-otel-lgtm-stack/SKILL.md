---
name: cno-otel-lgtm-stack
description: OpenTelemetry Collector spanmetrics, Prometheus, Loki TSDB v13, Tempo, and Grafana dashboard configuration patterns for github.com/abeta-dev/cloud-native-observability (v0.3.0).
---

# `cno-otel-lgtm-stack` Subskill (`v0.3.0`)

Key configuration paths:
- `compose.yaml` & `deploy/docker-compose/docker-compose.yml`
- `deploy/docker-compose/otel-collector/otel-collector-config.yml` & `deploy/kubernetes/helm/otel-collector/values.yaml`
- `deploy/docker-compose/prometheus/prometheus.yml`
- `deploy/docker-compose/loki/loki-config.yml` & `deploy/kubernetes/helm/loki/values.yaml`
- `deploy/docker-compose/tempo/tempo-config.yml` & `deploy/kubernetes/helm/tempo/values.yaml`
- `deploy/docker-compose/grafana/provisioning/datasources/datasources.yml`
- `deploy/docker-compose/grafana/dashboards/microservice-apm.json`, `deploy/docker-compose/grafana/dashboards/platform-overview.json`, & `deploy/docker-compose/grafana/dashboards/logs-explorer.json`

## 1. OpenTelemetry Collector Pipeline (`deploy/docker-compose/otel-collector/otel-collector-config.yml`)

- **Receivers**: `otlp` on `0.0.0.0:4317` (gRPC) and `0.0.0.0:4318` (HTTP).
- **Processors**:
  - `memory_limiter` MUST be first in every pipeline (`traces`, `metrics`, `logs`) to prevent OOM kills under traffic spikes.
  - `k8sattributes` (in `deploy/kubernetes/helm/otel-collector/values.yaml`) or `resource` (in Docker Compose) enriches telemetry with pod/environment metadata.
  - `batch` groups outgoing telemetry before export.
- **Connectors**:
  - `spanmetrics` and `servicegraph` consume `traces` and emit RED metrics to the `metrics` pipeline.
- **Exporters**:
  - `otlp/tempo` (`tempo:4317` in Compose; `tempo-distributor.tracing.svc.cluster.local:4317` in Kubernetes) for traces
  - `prometheus` (`0.0.0.0:8889` with `namespace: traces_spanmetrics`) for span-derived metrics
  - `otlphttp/loki` (`http://loki:3100/otlp` in Compose; `http://loki-gateway.logging.svc.cluster.local/otlp` in Kubernetes) for structured logs

## 2. Loki TSDB `v13` & High-Cardinality Guardrails (`deploy/docker-compose/loki/loki-config.yml`)

- Uses schema `v13` with `store: tsdb` and `allow_structured_metadata: true`.
- **Cardinality Rule**: Keep Loki stream labels restricted to low-cardinality resource attributes (`service.name`, `service`, `app`, `deployment.environment`, `environment`, `level`). Store `trace_id`, `span_id`, `request_id`, `traceId`, `spanId`, and `requestId` in **structured metadata**, never as indexed stream labels.

## 3. OpenTelemetry Collector `spanmetrics` Connector (`:8889`)

- The OpenTelemetry Collector `spanmetrics` connector synthesizes RED metrics from OTLP trace spans and exposes them via the `prometheus` exporter on `:8889` (`namespace: traces_spanmetrics`).
- When querying trace-derived span metrics in Grafana (`deploy/docker-compose/grafana/dashboards/microservice-apm.json`) or Prometheus rules, always query `traces_spanmetrics_calls_total` and `traces_spanmetrics_duration_milliseconds_bucket`.

## 4. Grafana Datasource & Dashboard Provisioning (`deploy/docker-compose/grafana/`)

- Datasources (`deploy/docker-compose/grafana/provisioning/datasources/datasources.yml`) pre-wire:
  - Loki derived fields / structured metadata → Tempo (`trace_id`)
  - Tempo `tracesToLogsV2` & `serviceMap` → Loki & Prometheus
- All dashboard PromQL queries in `deploy/docker-compose/grafana/dashboards/*.json` and `deploy/terraform/modules/grafana_provisioning/files/microservice-golden-signals.json` are statically validated against the exported metrics catalog by `./scripts/check_version.sh`.

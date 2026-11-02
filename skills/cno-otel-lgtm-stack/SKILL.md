---
name: cno-otel-lgtm-stack
description: OpenTelemetry Collector, Prometheus, Loki TSDB v13, Tempo spanmetrics, and Grafana dashboard configuration patterns for github.com/Abeta-dev/cloud-native-observability (v0.2.4).
---

# `cno-otel-lgtm-stack` Subskill (`v0.2.4`)

Key configuration paths:
- `configs/otel-collector/otel-collector-config.yaml`
- `configs/prometheus/prometheus.yml`
- `configs/loki/loki-config.yaml`
- `configs/tempo/tempo-config.yaml`
- `configs/grafana/provisioning/` & `configs/grafana/dashboards/`

## 1. OpenTelemetry Collector Pipeline (`configs/otel-collector/otel-collector-config.yaml`)

- **Receivers**: `otlp` on `0.0.0.0:4317` (gRPC) and `0.0.0.0:4318` (HTTP).
- **Processors**:
  - `memory_limiter` MUST be first in every pipeline (`traces`, `metrics`, `logs`) to prevent OOM kills under traffic spikes.
  - `transform/logs` parses JSON log bodies and promotes `trace_id`, `span_id`, and `request_id` to resource/log attributes so Loki indexes them as structured metadata without high-cardinality stream labels.
  - `batch` groups outgoing telemetry before export.
- **Exporters**:
  - `otlp/tempo` (`tempo:4317`) for traces
  - `prometheusremotewrite` (`http://prometheus:9090/api/v1/write`) for OTLP metrics
  - `otlphttp/loki` (`http://loki:3100/otlp`) for structured logs

## 2. Loki TSDB `v13` & High-Cardinality Guardrails (`configs/loki/loki-config.yaml`)

- Uses schema `v13` with `store: tsdb` and `allow_structured_metadata: true`.
- **Cardinality Rule**: Keep Loki stream labels restricted to low-cardinality resource attributes (`service_name`, `deployment_environment`, `severity_text`). Store `trace_id`, `span_id`, `request_id`, and `user_id` in **structured metadata**, never as indexed stream labels.

## 3. Tempo `metrics_generator` & Spanmetrics (`configs/tempo/tempo-config.yaml`)

- Tempo generates RED span metrics and remote-writes them to Prometheus.
- When querying Tempo-generated span call counts in Grafana or Prometheus rules, always query `traces_spanmetrics_calls_total` and `traces_spanmetrics_latency_bucket`.

## 4. Grafana Datasource & Dashboard Provisioning (`configs/grafana/`)

- Datasources (`datasources.yaml`) pre-wire:
  - Prometheus exemplar links → Tempo (`traceID`)
  - Loki derived fields / structured metadata → Tempo (`trace_id`)
  - Tempo service graph & span-to-logs → Loki & Prometheus
- Any dashboard panel displaying HTTP availability/error rate in `service-golden-signals.json` must stay AST-equivalent to the canonical availability SLI in `recording_rules.yml`.

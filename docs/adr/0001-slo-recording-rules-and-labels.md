# ADR 0001: Precomputed SLO Recording Rules, Routing Label Preservation, and High-Cardinality Telemetry Isolation

- **Status**: Accepted
- **Date**: 2026-09-08
- **Deciders**: SRE Architecture Team, Observability Platform Guild
- **Consulted**: Security, Backend Engineering

---

## Context and Problem Statement

The enterprise observability platform monitors hundreds of microservice instances using Prometheus, Grafana Loki, Grafana Tempo, and OpenTelemetry Collector. A core objective is implementing Google SRE Chapter 5 multi-window multi-burn-rate alerting for a **99.9% Service Level Objective (SLO)**.

Multi-window burn-rate alerts require evaluating error budget consumption across overlapping short and long windows:
- 1-hour burn rate (14.4x) evaluated over 1h and 5m
- 6-hour burn rate (6x) evaluated over 6h and 30m
- 3-day burn rate (1x) evaluated over 3d and 6h

However, continuous alert evaluation over long windows introduces significant platform risks:
1. **TSDB Query Exhaustion & Evaluation Timeouts**: Executing ad-hoc PromQL queries over 6 hours or 3 days of raw time-series (`http_requests_total`) every 15–60 seconds causes CPU spikes, query timeouts, and missed alert cycles.
2. **Label Stripping & Routing Breakage**: Aggregating metrics with unqualified `sum(...)` strips identity labels (`service`, `namespace`, `severity`), preventing Alertmanager from routing critical pages to the responsible engineering squads.
3. **Cardinality Explosions in Log Storage**: Microservices emit millions of structured log lines containing correlation IDs (`trace_id`, `span_id`, `request_id`). Indexing these unique IDs as standard Loki stream labels creates millions of discrete streams, exhausting memory and causing index compaction failure.

## Decision Drivers

- **Reliable SRE Alerting**: 100% dependable alert evaluation without PromQL timeouts or skipped evaluation intervals.
- **Accurate Notification Routing**: Preserve service identity, environment, and tier labels throughout the alerting pipeline for Alertmanager grouping and dispatch.
- **Index Efficiency & Cost Control**: Support deep searchability of high-cardinality identifiers without exploding TSDB storage costs.
- **Unified Telemetry Synthesis**: Automatically derive RED metrics (Rate, Errors, Duration) from distributed traces without requiring manual code changes in every service.

## Considered Options

1. **Option 1**: Direct ad-hoc PromQL evaluation across all windows without recording rules.
2. **Option 2**: External SLO calculator service querying Prometheus via REST API.
3. **Option 3**: In-cluster Prometheus Recording Rules for precomputed error rates, explicit routing label preservation, and Loki Structured Metadata partitioning.

## Decision Outcome

**Chosen Option: Option 3 (Prometheus Recording Rules + Label Preservation + Structured Metadata).**

### 1. Precomputed Recording Rules (`slo.availability.recording`)

Rather than scanning raw samples across multi-hour ranges repeatedly, Prometheus recording rules precompute and store error ratios as lightweight time-series:

```yaml
groups:
  - name: slo.availability.recording
    rules:
      - record: job:http_requests:error_rate_5m
        expr: sum(rate(http_requests_total{status=~"5.."}[5m])) by (service, namespace) / sum(rate(http_requests_total[5m])) by (service, namespace)
      - record: job:http_requests:error_rate_30m
        expr: sum(rate(http_requests_total{status=~"5.."}[30m])) by (service, namespace) / sum(rate(http_requests_total[30m])) by (service, namespace)
      - record: job:http_requests:error_rate_1h
        expr: sum(rate(http_requests_total{status=~"5.."}[1h])) by (service, namespace) / sum(rate(http_requests_total[1h])) by (service, namespace)
      - record: job:http_requests:error_rate_6h
        expr: sum(rate(http_requests_total{status=~"5.."}[6h])) by (service, namespace) / sum(rate(http_requests_total[6h])) by (service, namespace)
      - record: job:http_requests:error_rate_3d
        expr: sum(rate(http_requests_total{status=~"5.."}[3d])) by (service, namespace) / sum(rate(http_requests_total[3d])) by (service, namespace)
```

Burn-rate alerting rules then evaluate these precomputed error rate metrics, reducing query execution time from seconds to sub-milliseconds.

### 2. Label Preservation & Routing Strategy

Telemetry dimensionality and operational notification metadata are cleanly partitioned:
- **Metric Dimension Preservation**: Recording rules explicitly aggregate via `by (service, namespace)`, ensuring precomputed error rates retain service identity and deployment namespace.
- **Alert Routing Metadata**: Alert rules bind operational routing labels at definition time:
  - `severity`: Differentiates immediate pages (`critical`) from ticket warnings (`warning`).
  - `tier`: Categorizes service impact level (e.g. `tier: slo`).
- **Alertmanager Inhibit Rules**: Inhibit rules leverage matching `equal: ["alertname", "cluster", "service", "namespace"]` to prevent duplicate warning notifications when a critical incident is actively firing on the same service.

### 3. Spanmetrics & Trace-Derived RED Metrics

The telemetry pipeline uses OpenTelemetry Collector and Tempo to synthesize RED metrics from distributed trace spans:
- `traces_spanmetrics_calls_total`
- `traces_spanmetrics_duration_milliseconds_bucket`

This enables automatic service dependency topology mapping and latency histogram analysis across all services without custom metric code.

### 4. Loki TSDB Indexing vs. Structured Metadata

Grafana Loki 3.0+ is configured with TSDB store (`schema: v13`) and 24-hour index tables. Cardinality is strictly controlled:

```yaml
limits_config:
  allow_structured_metadata: true
  otlp_config:
    resource_attributes:
      attributes_config:
        # Low cardinality: indexed into TSDB for fast stream selection
        - action: index_label
          attributes:
            - service.name
            - service
            - deployment.environment
            - environment
            - level
            - app
        # High cardinality: attached to records as structured metadata
        - action: structured_metadata
          attributes:
            - trace_id
            - request_id
            - span_id
            - traceId
            - requestId
            - spanId
```

This ensures log streams remain bounded (preventing out-of-memory crashes) while preserving sub-second LogQL filtering by `trace_id` and seamless trace-to-log jumps in Grafana.

## Consequences

### Positive
- **Predictable TSDB Performance**: Evaluates complex 30-day SLO compliance in sub-milliseconds without TSDB query exhaustion.
- **Resilient Incident Routing**: Zero dropped routing labels; alerts consistently arrive in the correct Slack channels and PagerDuty schedules.
- **Protected Log Infrastructure**: Structured metadata eliminates Loki high-cardinality stream explosion while preserving granular trace correlation.
- **Zero-Code Instrumentation**: Spans automatically populate RED metric dashboards and service dependency maps.

### Negative / Trade-offs
- **Storage Overhead**: Precomputed recording rules generate additional time-series in Prometheus (minimal overhead compared to raw sample scans).
- **Rule Synchronization**: Adding new SLO windows requires updating both the recording rule definitions and the alerting rule conditions.

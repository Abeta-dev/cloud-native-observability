# Downstream Microservice Integration Guide

This guide explains how to connect any microservice (specifically Go services using Abeta go-libs (github.com/umesh0492/go-libs)) to this centralized Cloud-Native Observability platform.

---

## 1. The Three Telemetry Pillars

To achieve full observability, every service must provide:
1. **Metrics**: Expose Prometheus OpenMetrics on `/metrics`.
2. **Logs**: Output structured JSON to `stdout` with `trace_id` fields.
3. **Traces**: Export OTLP spans over gRPC to the OpenTelemetry Collector on port `4317`.

---

## 2. Connecting `go-libs` Services in 3 Steps

### Step 1: Export OTLP Distributed Traces (`apm` + `ginmw.APM`)

Using the pluggable `apm` module from `go-libs`, plug in the OpenTelemetry exporter:

```go
package main

import (
    "context"
    "github.com/gin-gonic/gin"
    "github.com/umesh0492/go-libs/apm"
    "github.com/umesh0492/go-libs/ginmw"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/trace"
)

func initTracer(ctx context.Context) (*trace.TracerProvider, error) {
    // Connect to OTel Collector DaemonSet on port 4317
    exporter, err := otlptracegrpc.New(ctx,
        otlptracegrpc.WithInsecure(),
        otlptracegrpc.WithEndpoint("otel-collector:4317"),
    )
    if err != nil {
        return nil, err
    }
    tp := trace.NewTracerProvider(trace.WithBatcher(exporter))
    otel.SetTracerProvider(tp)
    return tp, nil
}
```

Attach the `ginmw.APM` middleware:
```go
router.Use(ginmw.APM(otelAdapter))
```

### Step 2: Structured JSON Logging with Trace Correlation (`logger`)

Ensure every log line contains `trace_id`:
```go
logger.Info(ctx, "processing order request",
    "order_id", "ord-9921",
    "trace_id", apm.SpanFromContext(ctx).TraceID(),
)
```

**Result in Grafana**:
When inspecting logs in Loki, Grafana automatically underlines the `trace_id` as a clickable hyperlink that opens the exact trace span in Grafana Tempo!

### Step 3: Kubernetes Metrics Scrape Contract (`ServiceMonitor`)

In the microservice Helm chart, enable `ServiceMonitor`:
```yaml
serviceMonitor:
  enabled: true
  interval: 15s
  path: /metrics
  labels:
    release: kube-prometheus-stack
```

---

## 3. Local Development Integration

When testing locally using Docker Compose, point downstream services to:
- **Metrics Scraper**: Prometheus auto-scrapes services defined in `deploy/docker-compose/prometheus/prometheus.yml`.
- **Trace Exporter**: `localhost:4317` (gRPC) or `localhost:4318` (HTTP).
- **Log Ingestion**: Loki endpoint at `http://localhost:3100/loki/api/v1/push`.

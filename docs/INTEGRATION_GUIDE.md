# Downstream Microservice Integration Guide

This guide explains how to connect any microservice (specifically Go services using Abeta `go-libs` (`github.com/Abeta-dev/go-libs`)) to this centralized Cloud-Native Observability platform.

---

## 1. The Three Telemetry Pillars

To achieve full observability, every service must provide:
1. **Metrics**: Expose Prometheus OpenMetrics on `/metrics`.
2. **Logs**: Output structured JSON to `stdout` with `trace_id` fields.
3. **Traces**: Export OTLP spans over gRPC to the OpenTelemetry Collector on port `4317`.

---

## 2. Connecting `go-libs` Services in 3 Steps

### Step 1: Export OTLP Distributed Traces (`telemetry` + `ginmw.Telemetry`)

Using `github.com/Abeta-dev/go-libs/telemetry`, initialize the OpenTelemetry tracer provider and register W3C Trace Context propagation:

```go
package main

import (
    "context"

    "github.com/Abeta-dev/go-libs/ginmw"
    "github.com/Abeta-dev/go-libs/telemetry"
    "github.com/gin-gonic/gin"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

func initTracer(ctx context.Context) (*telemetry.TracerProvider, func(context.Context) error, error) {
    // Create an instance-scoped TracerProvider configured with service metadata
    tp, cleanup, err := telemetry.NewTracerProvider(
        telemetry.WithServiceName("order-service"),
        telemetry.WithServiceVersion("0.3.0"),
        telemetry.WithEnvironment("production"),
        telemetry.WithSampleRate(1.0),
    )
    if err != nil {
        return nil, nil, err
    }

    // Or connect an OTLP gRPC exporter to the OTel Collector DaemonSet on port 4317
    exporter, err := otlptracegrpc.New(ctx,
        otlptracegrpc.WithInsecure(),
        otlptracegrpc.WithEndpoint("otel-collector:4317"),
    )
    if err != nil {
        return nil, nil, err
    }
    otelTP := sdktrace.NewTracerProvider(sdktrace.WithBatcher(exporter))
    telemetry.InitProvider(otelTP)
    return tp, cleanup, nil
}
```

Attach the `ginmw.Telemetry` middleware to automatically extract/inject W3C `traceparent` headers and normalize route labels (`c.FullPath()`):
```go
router := gin.New()
router.Use(ginmw.Telemetry("order-service"))
```

### Step 2: Structured JSON Logging with Trace Correlation (`logger` + `telemetry.StartSpan`)

Ensure every log line contains `trace_id` using `telemetry.StartSpan` and `logger.FromContext(ctx)`:
```go
ctx, span := telemetry.StartSpan(c.Request.Context(), "order-service", "process-order")
defer span.End()

logger.FromContext(ctx).InfoContext(ctx, "processing order request",
    "order_id", "ord-9921",
    "trace_id", span.SpanContext().TraceID().String(),
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
- **Log Ingestion**: Loki endpoint at `http://localhost:3100/loki/api/v1/push` (or via OTel Collector OTLP HTTP/gRPC -> `http://loki:3100/otlp`).

# OpenTelemetry Sampling Strategies Guide

In high-throughput microservice architectures, capturing 100% of all traces is cost-prohibitive and creates massive backend storage pressure. This guide explains the **trace sampling strategies** supported by the OpenTelemetry Collector and when to choose each.

---

## 🎯 Comparison Matrix

| Strategy | Decision Point | Overhead | 100% Error Capture | Cost Predictability | Best For |
|:---|:---|:---|:---|:---|:---|
| **Probabilistic Head Sampling** | Ingestion start ($t=0$) | Lowest (negligible CPU/RAM) | ❌ No (misses errors if unsampled) | High | Routine, high-volume APIs where statistical sampling is sufficient |
| **Tail-Based Multi-Rule Sampling** | Trace completion ($t = \text{end}$) | Medium (buffers traces in memory) | ✅ Yes (100% of errors & slow calls retained) | Medium | Mission-critical production services, SLAs, and troubleshooting |

---

## 🛠️ How to Deploy

The sampling configurations are provided in [sampling-strategies.yaml](../deploy/kubernetes/helm/otel-collector/sampling-strategies.yaml).

To apply a specific strategy with Helm or ArgoCD:

```bash
# Apply Tail-Based Sampling (Production Recommended)
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  -f deploy/kubernetes/helm/otel-collector/values.yaml \
  -f deploy/kubernetes/helm/otel-collector/sampling-strategies.yaml
```

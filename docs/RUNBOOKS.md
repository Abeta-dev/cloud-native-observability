# Incident Response Runbooks

Standard Operating Procedures (SOPs) for on-call SRE and Platform Engineers responding to alerts triggered by the Cloud-Native Observability stack.

---

## 1. High Urgency SLO & Burn Rate Alerts

### `ServiceErrorBudgetBurnRateHigh1h`
- **Severity**: `critical` (Immediate Page)
- **Condition**: Service error budget is burning at 14.4x over 1 hour and 5 minutes (consuming 2% of the monthly error budget in 1 hour).
- **Target SLA Impact**: 99.9% Availability violation within hours if unmitigated.
- **Triage Steps**:
  1. Open the [Platform Overview Dashboard](http://localhost:3000/d/platform-overview) and [Microservice APM](http://localhost:3000/d/microservice-apm).
  2. Inspect the HTTP 5xx error rate spike in Grafana.
  3. Filter Loki logs using: `{app=~"$service"} |= "error" or |= "status=500"`.
  4. Find the `trace_id` in the log output and click through to Tempo to inspect the failing span.
  5. Check recent deployment revisions: `kubectl rollout history deployment/<service-name> -n <namespace>`.
- **Mitigation**:
  - If triggered by a recent deployment: `kubectl rollout undo deployment/<service-name> -n <namespace>`.
  - If downstream database / external API failure: check circuit breaker state (`app_circuit_breaker_state`). If open, verify dependent service health.
  - If traffic surge / DDoS: scale up replicas: `kubectl scale deployment/<service-name> --replicas=<N>` or verify Cloudflare/WAF rate limits.

---

### `ServiceErrorBudgetBurnRateHigh6h`
- **Severity**: `critical` (Immediate Page)
- **Condition**: Service error budget burning at 6x over 6 hours (consuming 5% of monthly budget in 6 hours).
- **Triage Steps**:
  1. Check for subtle memory leaks or degraded database connection pools.
  2. Inspect p95/p99 latency trends: increasing latency often cascades into HTTP 504 timeouts.
  3. Query Loki for recurring intermittent errors: `sum(count_over_time({app=~"$service"} |= "timeout" [30m]))`.
- **Mitigation**:
  - Restart failing pods gracefully: `kubectl rollout restart deployment/<service-name> -n <namespace>`.
  - Check worker pool queue drop metrics (`app_workerpool_tasks_dropped_total`).

---

### `ServiceErrorBudgetBurnRateSlow3d`
- **Severity**: `warning` (Ticket / Daily Standup Triage)
- **Condition**: Service error budget burning at 1x over 3 days (consuming 10% of monthly budget over 3 days).
- **Triage Steps**:
  1. Inspect error trends across deployments over the last 72 hours.
  2. Identify low-volume background errors or specific route edge cases failing consistently.
  3. Check third-party API error rates and partner status pages.
- **Mitigation**:
  - File prioritized engineering backlog bug for edge-case request failures.
  - Tune timeout parameters or enhance retry jitter for flaky dependencies.

---

## 2. Infrastructure & Kubernetes Alerts

### `KubeNodeNotReady`
- **Severity**: `critical`
- **Condition**: Kubernetes worker node condition `Ready == false` for >5 minutes.
- **Triage Steps**:
  1. Describe node: `kubectl describe node <node-name>`.
  2. Inspect Kubelet systemd logs on node: `journalctl -u kubelet -e`.
  3. Check AWS EC2 / GCP Compute instance health status (system status checks).
- **Mitigation**:
  - Cordon and drain the node: `kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data`.
  - Terminate or reboot instance to trigger Auto Scaling Group (ASG) replacement.

---

### `KubeNodeDiskPressure`
- **Severity**: `critical`
- **Condition**: Worker node disk usage >90%.
- **Triage Steps**:
  1. Identify large containers: `docker system df` or `crictl inspectp`.
  2. Check directory utilization: `df -h` and `du -sh /var/lib/containerd/*`.
- **Mitigation**:
  - Run container runtime prune: `crictl rmi --prune`.
  - Clean rotated host logs in `/var/log`.

---

### `KubeNodeMemoryPressure`
- **Severity**: `critical`
- **Condition**: Worker node reporting MemoryPressure condition (`kube_node_status_condition{condition="MemoryPressure",status="true"} == 1`).
- **Triage Steps**:
  1. Identify top memory-consuming pods on the node: `kubectl top pods -A --sort-by=memory`.
  2. Inspect node kernel logs for OOM killer activity: `dmesg -T | grep -i oom`.
- **Mitigation**:
  - Drain or evict non-critical workloads to free node memory headroom.
  - Check for memory leaks in applications without configured limits.

---

### `KubePodCrashLooping`
- **Severity**: `critical`
- **Condition**: Pod restarting >2 times per minute for 5 minutes.
- **Triage Steps**:
  1. Inspect termination exit code: `kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'`.
  2. Check previous container logs: `kubectl logs <pod-name> -n <namespace> --previous --tail=100`.
  3. If exit code `137`: Container was killed by OOMKilled (Out of Memory).
- **Mitigation**:
  - If OOMKilled: Increase container memory limit in `values.yaml` or deployment manifest.
  - If exit code `1` or panic: Review recent code commits and roll back.

---

### `KubeDeploymentReplicasMismatch`
- **Severity**: `warning`
- **Condition**: Deployment available replicas mismatching desired replicas for >15 minutes (`kube_deployment_status_replicas_available != kube_deployment_spec_replicas`).
- **Triage Steps**:
  1. Describe failing deployment: `kubectl describe deployment <deployment-name> -n <namespace>`.
  2. Check ReplicaSet events for pending pods, insufficient cluster CPU/memory, or ImagePullBackOff.
- **Mitigation**:
  - Scale cluster node group if pods are unschedulable due to resource exhaustion.
  - Fix invalid image tags or image pull secrets.

---

## 3. Golden Signals & Microservice Alerts

### `ServiceDown`
- **Severity**: `critical` (Immediate Page)
- **Condition**: Service instance `up == 0` for >1 minute.
- **Target SLA Impact**: Complete instance outage; unserved user traffic.
- **Triage Steps**:
  1. Check container or pod status: `docker compose ps` or `kubectl get pods -n <namespace>`.
  2. Inspect container exit logs: `docker compose logs <service> --tail=100` or `kubectl logs <pod-name> -n <namespace> --previous`.
  3. Verify network connectivity, port accessibility, and target health check endpoints (`/-/healthy`, `/healthz`).
- **Mitigation**:
  - Restart the service instance: `docker compose restart <service>` or `kubectl rollout restart deployment/<service>`.
  - If container crashed due to OOM or unhandled exception, check memory headroom or roll back recent deployment.

<a id="high-error-rate"></a>
<a id="higherrorrate"></a>
### `HighErrorRate`
- **Severity**: `critical` (Immediate Page)
- **Condition**: HTTP 5xx error rate exceeds 1% (`> 0.01`) over a 5-minute rolling window (`rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.01`).
- **Target SLA Impact**: User request failure, degraded availability SLO.
- **Triage Steps**:
  1. Open [Microservice APM](http://localhost:3000/d/microservice-apm) in Grafana.
  2. Filter Loki logs for 5xx errors and trace back to failing endpoints or upstream services.
  3. Inspect circuit breaker status (`app_circuit_breaker_state`) and failure metrics (`app_circuit_breaker_failures_total`).
- **Mitigation**:
  - Roll back recent problematic releases or configuration changes.
  - If caused by downstream dependency failures, verify circuit breaker is isolating failures and fallback handlers are functioning.
  - Apply rate limiting or traffic shedding if under abnormal load.

---

### `HighLatencyP99`
- **Severity**: `warning` (Slack Alert / Investigation)
- **Condition**: P99 response duration exceeds 1.0 second over 5 minutes (`histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)) > 1.0`).
- **Target SLA Impact**: Slow user experience, potential client-side timeout cascades.
- **Triage Steps**:
  1. Inspect Tempo distributed traces for trace spans exceeding 1000ms.
  2. Check downstream database queries, lock contention, slow external API calls, or thread pool exhaustion.
  3. Verify host/container CPU utilization and CPU throttling (`container_cpu_cfs_throttled_periods_total`).
- **Mitigation**:
  - Scale horizontal service replicas: `kubectl scale deployment/<service> --replicas=<N>`.
  - Optimize slow database queries, add indexes, or increase connection pool limits.

---

### `WorkerpoolQueueNearFull`
- **Severity**: `warning` (Slack Alert)
- **Condition**: Asynchronous worker pool queue depth exceeds 85% of capacity (`workerpool_queue_depth / workerpool_queue_capacity > 0.85`).
- **Target SLA Impact**: Asynchronous task processing lag and risk of task drops.
- **Triage Steps**:
  1. Check worker pool task velocities (submitted vs completed) on [Microservice APM](http://localhost:3000/d/microservice-apm).
  2. Verify if worker goroutines are blocked on long-running I/O, deadlocks, or downstream timeouts.
  3. Check if any tasks have been dropped: `increase(app_workerpool_tasks_dropped_total[5m])`.
- **Mitigation**:
  - Increase worker pool concurrency (`WORKER_POOL_SIZE`) or queue capacity (`WORKER_QUEUE_CAP`).
  - Scale microservice replicas horizontally to distribute background processing load.

---

<a id="circuit-breaker-open"></a>
<a id="circuitbreakeropen"></a>
### `CircuitBreakerOpen`
- **Severity**: `warning` (Slack Alert / Investigation)
- **Condition**: Outbound dependency circuit breaker has tripped to the OPEN state (`app_circuit_breaker_state == 2`).
- **Target SLA Impact**: Degraded application feature availability; fallback behavior or degraded responses served to clients.
- **Triage Steps**:
  1. Identify the failing downstream integration or external dependency on the [Microservice APM](http://localhost:3000/d/microservice-apm) dashboard.
  2. Inspect Tempo traces for recent consecutive failed outbound spans.
  3. Verify whether the downstream service is returning 5xx server errors, connection timeouts, or TLS handshaking failures.
  4. Query Loki logs for recent outbound invocation errors: `{app="demo-app"} |= "circuit_breaker"`.
- **Mitigation**:
  - Confirm whether the third-party or internal dependent service is experiencing a recognized outage.
  - Verify circuit breaker fallback response mechanisms are executing gracefully without crashing caller goroutines.
  - Once downstream health is restored, observe transition from OPEN to HALF-OPEN to CLOSED.

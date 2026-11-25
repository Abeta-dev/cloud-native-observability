#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# End-to-End Telemetry Smoke Test (Cloud-Native Observability Stack)
# Starts Docker Compose stack, validates container health, generates traffic/faults,
# and verifies telemetry metrics via Prometheus HTTP API.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

COMPOSE_FILE="deploy/docker-compose/docker-compose.yml"
PROMETHEUS_URL="http://localhost:9090"
DEMO_APP_URL="http://localhost:8080"

# Cleanup trap to ensure stack is always stopped and cleaned up
cleanup() {
  local exit_code=$?
  echo ""
  echo "=============================================================================="
  if [ "${exit_code}" -eq 0 ]; then
    echo "🎉 [Smoke Test] SUCCESS: All observability telemetry assertions passed!"
  else
    echo "❌ [Smoke Test] FAILURE: Smoke test failed with exit code ${exit_code}."
    echo "--- Dumping container status ---"
    docker compose -f "${COMPOSE_FILE}" ps || true
    echo "--- Recent demo-app logs ---"
    docker compose -f "${COMPOSE_FILE}" logs --tail=40 demo-app || true
    echo "--- Recent prometheus logs ---"
    docker compose -f "${COMPOSE_FILE}" logs --tail=40 prometheus || true
  fi
  echo "🧹 [Smoke Test] Tearing down Docker Compose stack..."
  docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans || true
  exit "${exit_code}"
}
trap cleanup EXIT INT TERM

echo "=============================================================================="
echo "🚀 [Smoke Test] Phase 1: Launching Observability Stack via Docker Compose"
echo "=============================================================================="
docker compose -f "${COMPOSE_FILE}" up -d --build

echo "⏳ [Smoke Test] Waiting for core containers to report healthy status..."
WAIT_SECS=0
MAX_WAIT=90
while [ "${WAIT_SECS}" -lt "${MAX_WAIT}" ]; do
  PROM_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "${PROMETHEUS_URL}/-/healthy" 2>/dev/null || echo "000")
  APP_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "${DEMO_APP_URL}/healthz" 2>/dev/null || echo "000")

  if [ "${PROM_HEALTH}" = "200" ] && [ "${APP_HEALTH}" = "200" ]; then
    echo "✅ [Smoke Test] Prometheus and Demo-App are online and healthy (${WAIT_SECS}s elapsed)."
    break
  fi

  sleep 2
  WAIT_SECS=$((WAIT_SECS + 2))
done

if [ "${WAIT_SECS}" -ge "${MAX_WAIT}" ]; then
  echo "❌ [Smoke Test] Timeout waiting for containers to become healthy after ${MAX_WAIT}s."
  exit 1
fi

echo "=============================================================================="
echo "⚡ [Smoke Test] Phase 2: Generating Synthetic Load and Inducing Faults"
echo "=============================================================================="
echo "Sending synthetic traffic and faults to demo-app..."

# 1. Trigger circuit breaker state transition (trip consecutive errors to force StateOpen -> StateHalfOpen)
for _ in $(seq 1 5); do
  curl -s -o /dev/null "${DEMO_APP_URL}/api/v1/error" || true
done
# Allow circuit breaker watchdog / probe to observe transition
sleep 2

# 2. Burst concurrent tasks to saturate worker pool queue (capacity = 12) and trigger task drops
for i in $(seq 1 25); do
  curl -s -o /dev/null -X POST "${DEMO_APP_URL}/api/v1/tasks" \
    -H "Content-Type: application/json" \
    -d "{\"payload\":\"smoke-burst-${i}\"}" &
done
wait

# 3. Generate sustained mixed traffic for rate calculations over 1m window
echo "Generating sustained traffic across endpoints for rate metrics..."
END_TIME=$(( $(date +%s) + 40 ))
while [ "$(date +%s)" -lt "${END_TIME}" ]; do
  curl -s -o /dev/null "${DEMO_APP_URL}/api/v1/items" || true
  curl -s -o /dev/null "${DEMO_APP_URL}/api/v1/quotes" || true
  curl -s -o /dev/null "${DEMO_APP_URL}/api/v1/error" || true
  curl -s -o /dev/null -X POST "${DEMO_APP_URL}/api/v1/tasks" \
    -H "Content-Type: application/json" \
    -d "{\"payload\":\"sustained-task\"}" || true
  sleep 0.5
done

# Trigger another burst to ensure worker pool dropped tasks metric is firmly established
for i in $(seq 1 30); do
  curl -s -o /dev/null -X POST "${DEMO_APP_URL}/api/v1/tasks" \
    -H "Content-Type: application/json" \
    -d "{\"payload\":\"smoke-dropped-${i}\"}" &
done
wait

echo "=============================================================================="
echo "🔎 [Smoke Test] Phase 3: Asserting Prometheus Metrics via HTTP API"
echo "=============================================================================="

# Helper function to query Prometheus and validate assertions with polling
query_prometheus_assert() {
  local query="$1"
  local assertion_name="$2"
  local poll_timeout=60
  local interval=3
  local elapsed=0

  echo "Validating assertion: ${assertion_name}..."

  while [ "${elapsed}" -lt "${poll_timeout}" ]; do
    local encoded_query
    encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "${query}")
    local response
    response=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=${encoded_query}" 2>/dev/null || echo "{}")

    local status
    status=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    results = data.get('data', {}).get('result', [])
    if data.get('status') == 'success' and len(results) > 0:
        val = results[0].get('value', [0, ''])[1]
        print(f'PASS|{val}')
    else:
        print('FAIL|no_result')
except Exception as e:
    print(f'ERROR|{e}')
" "${response}")

    local result_flag="${status%%|*}"
    local result_val="${status#*|}"

    if [ "${result_flag}" = "PASS" ]; then
      echo "   ✅ Assertion passed: ${assertion_name} (metric value: ${result_val})"
      return 0
    fi

    sleep "${interval}"
    elapsed=$((elapsed + interval))
  done

  echo "   ❌ Assertion failed after ${poll_timeout}s: ${assertion_name}"
  echo "      Query: ${query}"
  return 1
}

# 1. Assert up{job="demo-app"} == 1
query_prometheus_assert 'up{job="demo-app"} == 1' 'demo-app target is UP (up{job="demo-app"} == 1)'

# 2. Assert rate(http_requests_total[1m]) > 0
query_prometheus_assert 'sum(rate(http_requests_total{job="demo-app"}[1m])) > 0' 'Total HTTP request rate > 0 (rate(http_requests_total[1m]) > 0)'

# 3. Assert Non-zero 5xx error rate: rate(http_requests_total{status=~"5.."}[1m]) > 0
query_prometheus_assert 'sum(rate(http_requests_total{status=~"5.."}[1m])) > 0' 'HTTP 5xx error rate > 0 (rate(http_requests_total{status=~"5.."}[1m]) > 0)'

# 4. Assert app_circuit_breaker_state reaches 1 at least once (or max_over_time >= 1)
query_prometheus_assert 'max_over_time(app_circuit_breaker_state[3m]) >= 1' 'Circuit breaker state transitioned (max_over_time(app_circuit_breaker_state[3m]) >= 1)'

# 5. Assert app_workerpool_tasks_dropped_total increments (> 0)
query_prometheus_assert 'app_workerpool_tasks_dropped_total > 0' 'Worker pool tasks dropped total > 0 (app_workerpool_tasks_dropped_total > 0)'

echo "=============================================================================="
echo "🎯 All 5 Prometheus telemetry assertions verified successfully!"
echo "=============================================================================="

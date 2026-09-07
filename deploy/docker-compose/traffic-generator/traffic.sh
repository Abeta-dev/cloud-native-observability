#!/bin/sh
# Synthetic Traffic Generator for Cloud-Native Observability Stack
# Generates a realistic mix of 2xx, 4xx, 5xx requests and async tasks to populate Grafana dashboards
# Compatible with POSIX sh and BusyBox ash (Alpine Linux / curlimages/curl)

TARGET_HOST="${TARGET_HOST:-http://demo-app:8080}"
SLEEP_INTERVAL="${SLEEP_INTERVAL:-1}"

# Seed pseudo-random generator with epoch seconds and process ID
_seed=$(date +%s 2>/dev/null || echo 12345)
_seed=$(( (_seed + $$) % 2147483647 ))
_counter=0
rand_val=0

# POSIX-compliant random number generator
next_rand() {
  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    _urand=$(od -An -N2 -i /dev/urandom 2>/dev/null | tr -d ' ')
    if [ -n "$_urand" ] && [ "$_urand" -ge 0 ] 2>/dev/null; then
      rand_val="$_urand"
      return 0
    fi
  fi
  # Linear Congruential Generator (LCG) fallback: pure integer arithmetic
  _counter=$(( _counter + 1 ))
  _seed=$(( (_seed * 1103515245 + 12345 + _counter) % 2147483647 ))
  if [ "$_seed" -lt 0 ]; then
    _seed=$(( -_seed ))
  fi
  rand_val="$_seed"
}

echo "Starting Synthetic Traffic Generator targeting: ${TARGET_HOST}"

while true; do
  next_rand

  # 1. Successful items query (2xx)
  curl -s -o /dev/null "${TARGET_HOST}/api/v1/items" > /dev/null 2>&1

  # 2. Async worker pool task submission (202 Accepted)
  curl -s -o /dev/null -X POST "${TARGET_HOST}/api/v1/tasks" \
    -H "Content-Type: application/json" \
    -d "{\"payload\":\"task-${rand_val}\"}" > /dev/null 2>&1

  # 3. Circuit-breaker protected quotes endpoint (2xx, or 503 degraded when tripped)
  curl -s -o /dev/null "${TARGET_HOST}/api/v1/quotes" > /dev/null 2>&1

  # 4. Occasional invalid endpoint request (generates 404 client error metrics ~25% of iterations)
  if [ $(( rand_val % 4 )) -eq 0 ]; then
    curl -s -o /dev/null "${TARGET_HOST}/api/v1/invalid-endpoint" > /dev/null 2>&1
  fi

  # 5. Periodic server error (generates 500 metrics and error log lines in Loki)
  if [ $(( rand_val % 5 )) -eq 0 ]; then
    curl -s -o /dev/null "${TARGET_HOST}/api/v1/error" > /dev/null 2>&1
  fi

  # 6. Error burst simulation to trigger circuit breaker state transitions (Closed -> Open)
  if [ $(( rand_val % 10 )) -eq 0 ]; then
    curl -s -o /dev/null "${TARGET_HOST}/api/v1/error" > /dev/null 2>&1
    curl -s -o /dev/null "${TARGET_HOST}/api/v1/error" > /dev/null 2>&1
    curl -s -o /dev/null "${TARGET_HOST}/api/v1/error" > /dev/null 2>&1
  fi

  # 7. Task flood simulation to saturate worker pool backlog and emit dropped task metrics
  if [ $(( rand_val % 8 )) -eq 0 ]; then
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
      curl -s -o /dev/null -X POST "${TARGET_HOST}/api/v1/tasks" \
        -H "Content-Type: application/json" \
        -d "{\"payload\":\"flood-${i}-${rand_val}\"}" > /dev/null 2>&1 &
    done
  fi

  sleep "${SLEEP_INTERVAL}"
done

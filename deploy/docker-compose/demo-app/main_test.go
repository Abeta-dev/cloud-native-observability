package main

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestStateString(t *testing.T) {
	if got := stateString(StateClosed); got != "CLOSED" {
		t.Fatalf("expected CLOSED, got %s", got)
	}
	if got := stateString(StateHalfOpen); got != "HALF-OPEN" {
		t.Fatalf("expected HALF-OPEN, got %s", got)
	}
	if got := stateString(StateOpen); got != "OPEN" {
		t.Fatalf("expected OPEN, got %s", got)
	}
	if got := stateString(99); got != "UNKNOWN" {
		t.Fatalf("expected UNKNOWN, got %s", got)
	}
}

func TestCircuitBreakerLifecycleAndWatchdog(t *testing.T) {
	var logsReceived atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		logsReceived.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	otelEndpoint = srv.URL
	c := newCircuitBreaker()
	c.openTimeout = 10 * time.Millisecond

	// Closed -> allow request & record success
	allowed, st := c.AllowRequest("trace-1")
	if !allowed || st != StateClosed {
		t.Fatalf("expected allowed in CLOSED state, got allowed=%v state=%d", allowed, st)
	}
	c.RecordSuccess("trace-1")

	// 3 consecutive failures trip CLOSED -> OPEN
	c.RecordFailure("trace-f1")
	c.RecordFailure("trace-f2")
	c.RecordFailure("trace-f3")
	if c.state != StateOpen {
		t.Fatalf("expected StateOpen after 3 failures, got %d", c.state)
	}

	// While open before timeout -> disallow request
	c.openedAt = time.Now().Add(1 * time.Hour)
	allowed, st = c.AllowRequest("trace-blocked")
	if allowed || st != StateOpen {
		t.Fatalf("expected blocked in OPEN state, got allowed=%v state=%d", allowed, st)
	}

	// After openTimeout -> AllowRequest transitions OPEN -> HALF-OPEN
	c.openedAt = time.Now().Add(-1 * time.Second)
	allowed, st = c.AllowRequest("trace-probe")
	if !allowed || st != StateHalfOpen {
		t.Fatalf("expected allowed in HALF-OPEN state, got allowed=%v state=%d", allowed, st)
	}

	// Failure in HALF-OPEN trips back to OPEN
	c.RecordFailure("trace-probe-fail")
	if c.state != StateOpen {
		t.Fatalf("expected StateOpen after HALF-OPEN failure, got %d", c.state)
	}

	// Watchdog transitions OPEN -> HALF-OPEN after timeout
	c.openedAt = time.Now().Add(-1 * time.Second)
	ctx, cancel := context.WithCancel(context.Background())
	c.StartWatchdog(ctx, 5*time.Millisecond)
	deadline := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(deadline) {
		c.mu.Lock()
		curr := c.state
		c.mu.Unlock()
		if curr == StateHalfOpen {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	cancel()
	time.Sleep(10 * time.Millisecond)

	c.mu.Lock()
	if c.state != StateHalfOpen {
		c.mu.Unlock()
		t.Fatalf("expected watchdog to transition to StateHalfOpen, got %d", c.state)
	}
	c.mu.Unlock()

	// 2 consecutive successes in HALF-OPEN recover to CLOSED
	c.RecordSuccess("trace-s1")
	c.RecordSuccess("trace-s2")
	if c.state != StateClosed {
		t.Fatalf("expected StateClosed after 2 successes, got %d", c.state)
	}

	otlpWG.Wait()
	if logsReceived.Load() == 0 {
		t.Fatalf("expected OTLP logs to be received")
	}
}

func TestInitAppAndOTLPDispatch(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
	initApp(ctx)
	if otelEndpoint != "http://otel-collector:4318" {
		t.Fatalf("expected default otelEndpoint, got %s", otelEndpoint)
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", srv.URL)
	initApp(ctx)
	if otelEndpoint != srv.URL {
		t.Fatalf("expected custom otelEndpoint %s, got %s", srv.URL, otelEndpoint)
	}

	// Test sendOTLPLog with all severity levels and attribute value types
	sendOTLPLog("trace-abc", "span-def", slog.LevelDebug, "debug msg",
		"int_k", 1,
		"int64_k", int64(2),
		"uint64_k", uint64(3),
		"float64_k", 4.5,
		"bool_k", true,
		"str_k", "val",
	)
	sendOTLPLog("", "", slog.LevelWarn, "warn msg")
	sendOTLPLog("trace-err", "span-err", slog.LevelError, "err msg")

	// Test postOTLP error branches: invalid URL and unreachable server
	otelEndpoint = "://invalid-url"
	postOTLP("/v1/logs", map[string]any{"test": "invalid"})

	otelEndpoint = "http://127.0.0.1:1"
	postOTLP("/v1/logs", map[string]any{"test": "unreachable"})

	otelEndpoint = srv.URL

	// Test saturated otlpSem drop branch in dispatchOTLP
	otlpWG.Wait()
	for i := 0; i < maxOTLPConcurrency; i++ {
		otlpSem <- struct{}{}
	}
	var executed atomic.Bool
	dispatchOTLP(func() {
		executed.Store(true)
	})
	for i := 0; i < maxOTLPConcurrency; i++ {
		<-otlpSem
	}
	if executed.Load() {
		t.Fatalf("expected task to be dropped when otlpSem is full")
	}
}

func TestHTTPHandlersAndServer(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()
	otelEndpoint = srv.URL

	taskExecDelay = 5 * time.Millisecond
	cb = newCircuitBreaker()
	metrics.poolQueueDepth.Store(1)

	handler := newHandler()

	// 1. /healthz
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK || rec.Body.String() != "ok" {
		t.Fatalf("unexpected /healthz response: %d %s", rec.Code, rec.Body.String())
	}

	// 2. /api/v1/items
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/v1/items", nil)
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "Telemetry Gateway") {
		t.Fatalf("unexpected /api/v1/items response: %d %s", rec.Code, rec.Body.String())
	}

	// 3. /api/v1/tasks (accepted)
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, "/api/v1/tasks", nil)
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("expected 202 from /api/v1/tasks, got %d", rec.Code)
	}
	time.Sleep(20 * time.Millisecond)

	// 4. /api/v1/tasks (saturated -> 429)
	metrics.poolQueueDepth.Store(maxWorkerQueueCapacity)
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, "/api/v1/tasks", nil)
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429 when queue saturated, got %d", rec.Code)
	}
	metrics.poolQueueDepth.Store(2)

	// 5. /api/v1/quotes (healthy when CB closed)
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/v1/quotes", nil)
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "healthy") {
		t.Fatalf("expected 200 healthy from /api/v1/quotes, got %d %s", rec.Code, rec.Body.String())
	}

	// 6. /api/v1/error (3 times to trip circuit breaker to OPEN)
	for i := 0; i < 3; i++ {
		rec = httptest.NewRecorder()
		req = httptest.NewRequest(http.MethodGet, "/api/v1/error", nil)
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusInternalServerError {
			t.Fatalf("expected 500 from /api/v1/error, got %d", rec.Code)
		}
	}

	// 7. /api/v1/quotes (degraded 503 when CB open)
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/v1/quotes", nil)
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusServiceUnavailable || !strings.Contains(rec.Body.String(), "degraded") {
		t.Fatalf("expected 503 degraded from /api/v1/quotes when CB open, got %d %s", rec.Code, rec.Body.String())
	}

	// 8. 404 fallback route
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/does-not-exist", nil)
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for unknown route, got %d", rec.Code)
	}

	// 9. /metrics
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/metrics", nil)
	handler.ServeHTTP(rec, req)
	body, _ := io.ReadAll(rec.Result().Body)
	metricsText := string(body)
	for _, expectedMetric := range []string{
		"http_requests_total",
		"http_request_duration_seconds_bucket",
		"app_workerpool_queue_depth",
		"app_workerpool_queue_capacity",
		"app_circuit_breaker_requests_total",
		"app_circuit_breaker_failures_total",
		"app_circuit_breaker_state",
		"app_workerpool_tasks_submitted_total",
		"app_workerpool_tasks_completed_total",
		"app_workerpool_tasks_dropped_total",
		"app_cache_hits_total",
		"app_cache_misses_total",
	} {
		if !strings.Contains(metricsText, expectedMetric) {
			t.Fatalf("missing expected metric %q in /metrics output", expectedMetric)
		}
	}

	otlpWG.Wait()
}

func TestMainFunc(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()
	otelEndpoint = srv.URL

	origListen := listenAndServe
	origExit := exitFunc
	defer func() {
		listenAndServe = origListen
		exitFunc = origExit
	}()

	var capturedAddr string
	listenAndServe = func(addr string, handler http.Handler) error {
		capturedAddr = addr
		return nil
	}
	exitCode := 0
	exitFunc = func(code int) {
		exitCode = code
	}

	t.Setenv("PORT", "")
	main()
	if capturedAddr != ":8080" || exitCode != 0 {
		t.Fatalf("expected :8080 and exitCode 0, got addr=%s exitCode=%d", capturedAddr, exitCode)
	}

	t.Setenv("PORT", "9099")
	listenAndServe = func(addr string, handler http.Handler) error {
		capturedAddr = addr
		return errors.New("simulated listen error")
	}
	main()
	if capturedAddr != ":9099" || exitCode != 1 {
		t.Fatalf("expected :9099 and exitCode 1, got addr=%s exitCode=%d", capturedAddr, exitCode)
	}

	otlpWG.Wait()
}

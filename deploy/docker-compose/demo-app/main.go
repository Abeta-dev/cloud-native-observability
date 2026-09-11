package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	StateClosed   int64 = 0
	StateHalfOpen int64 = 1
	StateOpen     int64 = 2

	maxWorkerQueueCapacity int64 = 12
)

type Metrics struct {
	http2xx         atomic.Uint64
	http4xx         atomic.Uint64
	http5xx         atomic.Uint64
	durationBuckets [11]atomic.Uint64 // 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10
	durationSum     atomic.Uint64     // in microseconds
	breakerReqs     atomic.Uint64
	breakerFails    atomic.Uint64
	breakerState    atomic.Int64 // 0=Closed, 1=Half-Open, 2=Open
	poolSubmitted   atomic.Uint64
	poolCompleted   atomic.Uint64
	poolDropped     atomic.Uint64
	poolQueueDepth  atomic.Int64
	cacheHits       atomic.Uint64
	cacheMisses     atomic.Uint64
}

type CircuitBreaker struct {
	mu                sync.Mutex
	state             int64
	consecutiveErrors int
	openedAt          time.Time
	halfOpenSuccesses int
	openTimeout       time.Duration
	failureThreshold  int
	successThreshold  int
}

var (
	leThresholds = []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0}
	metrics      = &Metrics{}
	logger       *slog.Logger
	otelEndpoint string
	cb           *CircuitBreaker
	httpClient   = &http.Client{Timeout: 2 * time.Second}
)

func newCircuitBreaker() *CircuitBreaker {
	c := &CircuitBreaker{
		state:            StateClosed,
		openTimeout:      5 * time.Second,
		failureThreshold: 3,
		successThreshold: 2,
	}
	metrics.breakerState.Store(StateClosed)
	return c
}

func (c *CircuitBreaker) RecordFailure(traceID string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	metrics.breakerFails.Add(1)

	if c.state == StateClosed {
		c.consecutiveErrors++
		if c.consecutiveErrors >= c.failureThreshold {
			c.state = StateOpen
			c.openedAt = time.Now()
			metrics.breakerState.Store(StateOpen)
			emitLog(slog.LevelError, "circuit_breaker tripped: state changed from CLOSED to OPEN", traceID, "",
				"service", "demo-app",
				"app", "demo-app",
				"circuit_breaker", "OPEN",
				"state", StateOpen,
				"consecutive_errors", c.consecutiveErrors,
			)
		}
	} else if c.state == StateHalfOpen {
		c.state = StateOpen
		c.openedAt = time.Now()
		c.halfOpenSuccesses = 0
		metrics.breakerState.Store(StateOpen)
		emitLog(slog.LevelError, "circuit_breaker probe failed: state changed from HALF-OPEN to OPEN", traceID, "",
			"service", "demo-app",
			"app", "demo-app",
			"circuit_breaker", "OPEN",
			"state", StateOpen,
		)
	}
}

func (c *CircuitBreaker) RecordSuccess(traceID string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.state == StateHalfOpen {
		c.halfOpenSuccesses++
		if c.halfOpenSuccesses >= c.successThreshold {
			c.state = StateClosed
			c.consecutiveErrors = 0
			c.halfOpenSuccesses = 0
			metrics.breakerState.Store(StateClosed)
			emitLog(slog.LevelInfo, "circuit_breaker recovered: state changed from HALF-OPEN to CLOSED", traceID, "",
				"service", "demo-app",
				"app", "demo-app",
				"circuit_breaker", "CLOSED",
				"state", StateClosed,
			)
		}
	} else if c.state == StateClosed {
		c.consecutiveErrors = 0
	}
}

func (c *CircuitBreaker) AllowRequest(traceID string) (bool, int64) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.state == StateOpen {
		if time.Since(c.openedAt) >= c.openTimeout {
			c.state = StateHalfOpen
			c.halfOpenSuccesses = 0
			metrics.breakerState.Store(StateHalfOpen)
			emitLog(slog.LevelWarn, "circuit_breaker probe window reached: state changed from OPEN to HALF-OPEN", traceID, "",
				"service", "demo-app",
				"app", "demo-app",
				"circuit_breaker", "HALF-OPEN",
				"state", StateHalfOpen,
			)
			return true, StateHalfOpen
		}
		return false, StateOpen
	}

	return true, c.state
}

func (c *CircuitBreaker) StartWatchdog() {
	go func() {
		ticker := time.NewTicker(1 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			c.mu.Lock()
			if c.state == StateOpen && time.Since(c.openedAt) >= c.openTimeout {
				c.state = StateHalfOpen
				c.halfOpenSuccesses = 0
				metrics.breakerState.Store(StateHalfOpen)
				emitLog(slog.LevelWarn, "circuit_breaker watchdog: state transition from OPEN to HALF-OPEN", "", "",
					"service", "demo-app",
					"app", "demo-app",
					"circuit_breaker", "HALF-OPEN",
					"state", StateHalfOpen,
				)
			}
			c.mu.Unlock()
		}
	}()
}

func stateString(state int64) string {
	switch state {
	case StateClosed:
		return "CLOSED"
	case StateHalfOpen:
		return "HALF-OPEN"
	case StateOpen:
		return "OPEN"
	default:
		return "UNKNOWN"
	}
}

func init() {
	logger = slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	otelEndpoint = os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if otelEndpoint == "" {
		otelEndpoint = "http://otel-collector:4318"
	}
	metrics.poolQueueDepth.Store(2)
	cb = newCircuitBreaker()
	cb.StartWatchdog()
}

func randomHex(bytesLen int) string {
	b := make([]byte, bytesLen)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func emitLog(level slog.Level, msg string, traceID, spanID string, keyValues ...any) {
	// 1. Output structured JSON log to stdout
	fields := make([]any, 0, len(keyValues)+4)
	if traceID != "" {
		fields = append(fields, "trace_id", traceID)
	}
	if spanID != "" {
		fields = append(fields, "span_id", spanID)
	}
	fields = append(fields, keyValues...)
	logger.Log(context.Background(), level, msg, fields...)

	// 2. Dispatch OTLP log directly to OpenTelemetry Collector / Loki
	go sendOTLPLog(traceID, spanID, level, msg, keyValues...)
}

func sendOTLPLog(traceID, spanID string, level slog.Level, bodyMsg string, keyValues ...any) {
	nowNano := fmt.Sprintf("%d", time.Now().UnixNano())

	severityText := "INFO"
	severityNum := 9
	switch {
	case level >= slog.LevelError:
		severityText = "ERROR"
		severityNum = 17
	case level >= slog.LevelWarn:
		severityText = "WARN"
		severityNum = 13
	case level <= slog.LevelDebug:
		severityText = "DEBUG"
		severityNum = 5
	}

	attrs := make([]map[string]any, 0, (len(keyValues)/2)+2)
	attrs = append(attrs, map[string]any{"key": "app", "value": map[string]any{"stringValue": "demo-app"}})
	attrs = append(attrs, map[string]any{"key": "service.name", "value": map[string]any{"stringValue": "demo-app"}})

	for i := 0; i < len(keyValues)-1; i += 2 {
		k := fmt.Sprintf("%v", keyValues[i])
		v := keyValues[i+1]
		switch val := v.(type) {
		case int:
			attrs = append(attrs, map[string]any{"key": k, "value": map[string]any{"intValue": val}})
		case int64:
			attrs = append(attrs, map[string]any{"key": k, "value": map[string]any{"intValue": val}})
		case uint64:
			attrs = append(attrs, map[string]any{"key": k, "value": map[string]any{"intValue": int64(val)}})
		case float64:
			attrs = append(attrs, map[string]any{"key": k, "value": map[string]any{"doubleValue": val}})
		case bool:
			attrs = append(attrs, map[string]any{"key": k, "value": map[string]any{"boolValue": val}})
		default:
			attrs = append(attrs, map[string]any{"key": k, "value": map[string]any{"stringValue": fmt.Sprintf("%v", val)}})
		}
	}

	logRecord := map[string]any{
		"timeUnixNano":         nowNano,
		"observedTimeUnixNano": nowNano,
		"severityNumber":       severityNum,
		"severityText":         severityText,
		"body":                 map[string]any{"stringValue": bodyMsg},
		"attributes":           attrs,
	}
	if traceID != "" {
		logRecord["traceId"] = traceID
	}
	if spanID != "" {
		logRecord["spanId"] = spanID
	}

	payload := map[string]any{
		"resourceLogs": []map[string]any{
			{
				"resource": map[string]any{
					"attributes": []map[string]any{
						{"key": "service.name", "value": map[string]any{"stringValue": "demo-app"}},
						{"key": "service", "value": map[string]any{"stringValue": "demo-app"}},
						{"key": "app", "value": map[string]any{"stringValue": "demo-app"}},
						{"key": "deployment.environment", "value": map[string]any{"stringValue": "sandbox"}},
						{"key": "environment", "value": map[string]any{"stringValue": "local"}},
					},
				},
				"scopeLogs": []map[string]any{
					{
						"scope": map[string]any{
							"name":    "demo-app-logger",
							"version": "1.0.0",
						},
						"logRecords": []map[string]any{logRecord},
					},
				},
			},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return
	}

	req, err := http.NewRequest(http.MethodPost, otelEndpoint+"/v1/logs", bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := httpClient.Do(req)
	if err == nil && resp != nil {
		_ = resp.Body.Close()
	}
}

func sendOTLPSpan(traceID, spanID, name string, startTime, endTime time.Time, statusCode int) {
	go func() {
		startNano := uint64(startTime.UnixNano())
		endNano := uint64(endTime.UnixNano())

		statusMsg := "STATUS_CODE_OK"
		if statusCode >= 500 {
			statusMsg = "STATUS_CODE_ERROR"
		}

		payload := map[string]any{
			"resourceSpans": []map[string]any{
				{
					"resource": map[string]any{
						"attributes": []map[string]any{
							{"key": "service.name", "value": map[string]any{"stringValue": "demo-app"}},
							{"key": "service", "value": map[string]any{"stringValue": "demo-app"}},
							{"key": "app", "value": map[string]any{"stringValue": "demo-app"}},
							{"key": "deployment.environment", "value": map[string]any{"stringValue": "sandbox"}},
						},
					},
					"scopeSpans": []map[string]any{
						{
							"scope": map[string]any{"name": "demo-app-tracer", "version": "1.0.0"},
							"spans": []map[string]any{
								{
									"traceId":           traceID,
									"spanId":            spanID,
									"name":              name,
									"kind":              1, // SPAN_KIND_INTERNAL
									"startTimeUnixNano": fmt.Sprintf("%d", startNano),
									"endTimeUnixNano":   fmt.Sprintf("%d", endNano),
									"attributes": []map[string]any{
										{"key": "http.status_code", "value": map[string]any{"intValue": statusCode}},
										{"key": "http.method", "value": map[string]any{"stringValue": "GET"}},
										{"key": "http.route", "value": map[string]any{"stringValue": name}},
									},
									"status": map[string]any{
										"code": statusMsg,
									},
								},
							},
						},
					},
				},
			},
		}

		body, err := json.Marshal(payload)
		if err != nil {
			return
		}

		req, err := http.NewRequest(http.MethodPost, otelEndpoint+"/v1/traces", bytes.NewReader(body))
		if err != nil {
			return
		}
		req.Header.Set("Content-Type", "application/json")

		resp, err := httpClient.Do(req)
		if err == nil && resp != nil {
			_ = resp.Body.Close()
		}
	}()
}

func recordDuration(seconds float64) {
	metrics.durationSum.Add(uint64(seconds * 1_000_000))
	for i, t := range leThresholds {
		if seconds <= t {
			metrics.durationBuckets[i].Add(1)
		}
	}
}

func withInstrumentation(name string, handler func(w http.ResponseWriter, r *http.Request)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		traceID := randomHex(16)
		spanID := randomHex(8)

		r.Header.Set("X-Trace-ID", traceID)
		w.Header().Set("X-Trace-ID", traceID)

		// Capture status code
		rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}
		handler(rw, r)

		duration := time.Since(start).Seconds()
		recordDuration(duration)

		if rw.statusCode >= 200 && rw.statusCode < 300 {
			metrics.http2xx.Add(1)
		} else if rw.statusCode >= 400 && rw.statusCode < 500 {
			metrics.http4xx.Add(1)
		} else if rw.statusCode >= 500 {
			metrics.http5xx.Add(1)
		}

		// Emit structured log
		logLevel := slog.LevelInfo
		if rw.statusCode >= 500 {
			logLevel = slog.LevelError
		} else if rw.statusCode >= 400 {
			logLevel = slog.LevelWarn
		}

		emitLog(logLevel, "Processed HTTP request", traceID, spanID,
			"service", "demo-app",
			"app", "demo-app",
			"path", r.URL.Path,
			"status", rw.statusCode,
			"duration_ms", fmt.Sprintf("%.2f", duration*1000),
		)

		sendOTLPSpan(traceID, spanID, name, start, time.Now(), rw.statusCode)
	}
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func handleItems(w http.ResponseWriter, r *http.Request) {
	// Simulate cache lookup
	metrics.cacheHits.Add(3)
	metrics.cacheMisses.Add(1)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"items": []map[string]any{
			{"id": "item-101", "name": "Telemetry Gateway", "status": "active"},
			{"id": "item-102", "name": "Tracer Agent", "status": "active"},
		},
		"total": 2,
	})
}

func handleTasks(w http.ResponseWriter, r *http.Request) {
	traceID := r.Header.Get("X-Trace-ID")
	currentDepth := metrics.poolQueueDepth.Load()

	// Saturated backlog check: drop tasks if queue capacity is reached
	if currentDepth >= maxWorkerQueueCapacity {
		metrics.poolDropped.Add(1)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusTooManyRequests)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":       "dropped",
			"error":        "worker pool queue saturated, task dropped",
			"queue_depth":  currentDepth,
			"max_capacity": maxWorkerQueueCapacity,
		})
		emitLog(slog.LevelWarn, "Worker pool queue saturated, task dropped", traceID, "",
			"service", "demo-app",
			"app", "demo-app",
			"queue_depth", currentDepth,
			"max_capacity", maxWorkerQueueCapacity,
			"status", http.StatusTooManyRequests,
		)
		return
	}

	metrics.poolSubmitted.Add(1)
	metrics.poolQueueDepth.Add(1)

	// Simulate async execution
	go func() {
		time.Sleep(100 * time.Millisecond)
		metrics.poolCompleted.Add(1)
		if metrics.poolQueueDepth.Load() > 0 {
			metrics.poolQueueDepth.Add(-1)
		}
	}()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "task accepted into workerpool"})
}

func handleQuotes(w http.ResponseWriter, r *http.Request) {
	traceID := r.Header.Get("X-Trace-ID")
	metrics.breakerReqs.Add(1)

	allowed, state := cb.AllowRequest(traceID)
	if !allowed {
		metrics.breakerFails.Add(1)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":          "degraded",
			"circuit_breaker": "OPEN",
			"error":           "circuit breaker is OPEN: downstream quote provider unavailable",
			"fallback": map[string]any{
				"symbols": []string{"AAPL", "GOOG"},
				"notice":  "serving cached fallback quotes",
			},
		})
		emitLog(slog.LevelWarn, "circuit_breaker: short-circuited quote request while OPEN", traceID, "",
			"service", "demo-app",
			"app", "demo-app",
			"circuit_breaker", "OPEN",
			"status", http.StatusServiceUnavailable,
		)
		return
	}

	// Successful execution through circuit breaker
	cb.RecordSuccess(traceID)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"symbols":         []string{"AAPL", "GOOG"},
		"status":          "healthy",
		"circuit_breaker": stateString(state),
	})
}

func handleError(w http.ResponseWriter, r *http.Request) {
	traceID := r.Header.Get("X-Trace-ID")
	metrics.breakerReqs.Add(1)
	cb.RecordFailure(traceID)

	emitLog(slog.LevelError, "Synthetic upstream downstream timeout error", traceID, "",
		"service", "demo-app",
		"app", "demo-app",
		"circuit_breaker", stateString(metrics.breakerState.Load()),
		"path", r.URL.Path,
		"status", http.StatusInternalServerError,
		"error", "downstream timeout",
	)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusInternalServerError)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"error":           "synthetic upstream downstream timeout",
		"circuit_breaker": stateString(metrics.breakerState.Load()),
	})
}

func handleMetrics(w http.ResponseWriter, r *http.Request) {
	var sb strings.Builder

	sb.WriteString("# HELP up Service availability\n")
	sb.WriteString("# TYPE up gauge\n")
	sb.WriteString("up{service=\"demo-app\"} 1\n\n")

	sb.WriteString("# HELP http_requests_total Total number of HTTP requests processed\n")
	sb.WriteString("# TYPE http_requests_total counter\n")
	fmt.Fprintf(&sb, "http_requests_total{service=\"demo-app\",status=\"200\"} %d\n", metrics.http2xx.Load())
	fmt.Fprintf(&sb, "http_requests_total{service=\"demo-app\",status=\"404\"} %d\n", metrics.http4xx.Load())
	fmt.Fprintf(&sb, "http_requests_total{service=\"demo-app\",status=\"500\"} %d\n\n", metrics.http5xx.Load())

	sb.WriteString("# HELP http_request_duration_seconds HTTP request duration histogram\n")
	sb.WriteString("# TYPE http_request_duration_seconds histogram\n")
	var cumulative uint64
	for i, t := range leThresholds {
		cumulative += metrics.durationBuckets[i].Load()
		fmt.Fprintf(&sb, "http_request_duration_seconds_bucket{service=\"demo-app\",le=\"%.3f\"} %d\n", t, cumulative)
	}
	totalRequests := metrics.http2xx.Load() + metrics.http4xx.Load() + metrics.http5xx.Load()
	fmt.Fprintf(&sb, "http_request_duration_seconds_bucket{service=\"demo-app\",le=\"+Inf\"} %d\n", totalRequests)
	fmt.Fprintf(&sb, "http_request_duration_seconds_sum{service=\"demo-app\"} %.6f\n", float64(metrics.durationSum.Load())/1_000_000)
	fmt.Fprintf(&sb, "http_request_duration_seconds_count{service=\"demo-app\"} %d\n\n", totalRequests)

	sb.WriteString("# HELP app_workerpool_queue_depth Current worker pool queue depth\n")
	sb.WriteString("# TYPE app_workerpool_queue_depth gauge\n")
	fmt.Fprintf(&sb, "app_workerpool_queue_depth{service=\"demo-app\"} %d\n\n", metrics.poolQueueDepth.Load())

	sb.WriteString("# HELP app_workerpool_queue_capacity Maximum worker pool capacity\n")
	sb.WriteString("# TYPE app_workerpool_queue_capacity gauge\n")
	fmt.Fprintf(&sb, "app_workerpool_queue_capacity{service=\"demo-app\"} %d\n\n", maxWorkerQueueCapacity)

	sb.WriteString("# HELP app_circuit_breaker_requests_total Total requests through circuit breaker\n")
	sb.WriteString("# TYPE app_circuit_breaker_requests_total counter\n")
	fmt.Fprintf(&sb, "app_circuit_breaker_requests_total %d\n\n", metrics.breakerReqs.Load())

	sb.WriteString("# HELP app_circuit_breaker_failures_total Total failed requests through circuit breaker\n")
	sb.WriteString("# TYPE app_circuit_breaker_failures_total counter\n")
	fmt.Fprintf(&sb, "app_circuit_breaker_failures_total %d\n\n", metrics.breakerFails.Load())

	sb.WriteString("# HELP app_circuit_breaker_state Current state of circuit breaker (0=Closed, 1=Half-Open, 2=Open)\n")
	sb.WriteString("# TYPE app_circuit_breaker_state gauge\n")
	fmt.Fprintf(&sb, "app_circuit_breaker_state %d\n\n", metrics.breakerState.Load())

	sb.WriteString("# HELP app_workerpool_tasks_submitted_total Total submitted worker pool tasks\n")
	sb.WriteString("# TYPE app_workerpool_tasks_submitted_total counter\n")
	fmt.Fprintf(&sb, "app_workerpool_tasks_submitted_total %d\n\n", metrics.poolSubmitted.Load())

	sb.WriteString("# HELP app_workerpool_tasks_completed_total Total completed worker pool tasks\n")
	sb.WriteString("# TYPE app_workerpool_tasks_completed_total counter\n")
	fmt.Fprintf(&sb, "app_workerpool_tasks_completed_total %d\n\n", metrics.poolCompleted.Load())

	sb.WriteString("# HELP app_workerpool_tasks_dropped_total Total dropped worker pool tasks\n")
	sb.WriteString("# TYPE app_workerpool_tasks_dropped_total counter\n")
	fmt.Fprintf(&sb, "app_workerpool_tasks_dropped_total %d\n\n", metrics.poolDropped.Load())


	sb.WriteString("# HELP app_cache_hits_total Total cache hits\n")
	sb.WriteString("# TYPE app_cache_hits_total counter\n")
	fmt.Fprintf(&sb, "app_cache_hits_total %d\n\n", metrics.cacheHits.Load())

	sb.WriteString("# HELP app_cache_misses_total Total cache misses\n")
	sb.WriteString("# TYPE app_cache_misses_total counter\n")
	fmt.Fprintf(&sb, "app_cache_misses_total %d\n\n", metrics.cacheMisses.Load())

	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	_, _ = w.Write([]byte(sb.String()))
}

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	mux.HandleFunc("/metrics", handleMetrics)
	mux.HandleFunc("/api/v1/items", withInstrumentation("/api/v1/items", handleItems))
	mux.HandleFunc("/api/v1/tasks", withInstrumentation("/api/v1/tasks", handleTasks))
	mux.HandleFunc("/api/v1/quotes", withInstrumentation("/api/v1/quotes", handleQuotes))
	mux.HandleFunc("/api/v1/error", withInstrumentation("/api/v1/error", handleError))

	// Fallback 404 handler for invalid routes
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/healthz" && r.URL.Path != "/metrics" &&
			r.URL.Path != "/api/v1/items" && r.URL.Path != "/api/v1/tasks" &&
			r.URL.Path != "/api/v1/quotes" && r.URL.Path != "/api/v1/error" {
			withInstrumentation("not_found", func(w http.ResponseWriter, r *http.Request) {
				http.NotFound(w, r)
			})(w, r)
			return
		}
		mux.ServeHTTP(w, r)
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	emitLog(slog.LevelInfo, "Starting Demo Application server", "", "",
		"port", port,
		"otel_endpoint", otelEndpoint,
		"service", "demo-app",
		"app", "demo-app",
	)

	if err := http.ListenAndServe(":"+port, handler); err != nil {
		emitLog(slog.LevelError, "Server terminated unexpectedly", "", "", "error", err.Error())
		os.Exit(1)
	}
}

// Package telemetry exposes Prometheus metrics for PB1 (latency), PB2 (throughput), PB3 (CPU/RAM via process & runtime collectors).
package telemetry

import (
	"context"
	"net/http"
	"path"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"google.golang.org/grpc"
)

const namespace = "compare_api"

var (
	requestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Namespace: namespace,
			Name:      "request_duration_seconds",
			Help:      "PB1: end-to-end request latency in seconds.",
			Buckets:   append(prometheus.DefBuckets, 15, 30, 60),
		},
		[]string{"service", "operation"},
	)

	requestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Namespace: namespace,
			Name:      "requests_total",
			Help:      "PB2: total requests handled (use rate() for requests per second).",
		},
		[]string{"service", "operation", "status"},
	)
)

// Register adds PB1/PB2 series plus PB3 process and Go runtime collectors.
func Register(reg prometheus.Registerer) {
	reg.MustRegister(
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
		collectors.NewGoCollector(),
		requestDuration,
		requestsTotal,
	)
}

// ObserveRequest records latency and throughput for one logical operation.
func ObserveRequest(service, operation, status string, start time.Time) {
	if status == "" {
		status = "unknown"
	}
	requestDuration.WithLabelValues(service, operation).Observe(time.Since(start).Seconds())
	requestsTotal.WithLabelValues(service, operation, status).Inc()
}

// HTTPHandler wraps an http.Handler with PB1/PB2 instrumentation.
func HTTPHandler(service, operation string, h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sr := &statusRecorder{ResponseWriter: w, code: http.StatusOK}
		h.ServeHTTP(sr, r)
		st := "success"
		if sr.code >= http.StatusBadRequest {
			st = "error"
		}
		ObserveRequest(service, operation, st, start)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	code int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.code = code
	s.ResponseWriter.WriteHeader(code)
}

// UnaryServerInterceptor records gRPC unary RPC latency and counts (PB1/PB2).
func UnaryServerInterceptor(service string) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		start := time.Now()
		resp, err := handler(ctx, req)
		op := path.Base(info.FullMethod)
		st := "success"
		if err != nil {
			st = "error"
		}
		ObserveRequest(service, op, st, start)
		return resp, err
	}
}

package observability

import (
	"context"
	"time"

	"go.uber.org/zap"
)

// SimpleTracingProvider is a simplified tracing provider
type SimpleTracingProvider struct {
	ServiceName string
	logger      *zap.Logger
	enabled     bool
}

// SimpleSpan represents a simple span
type SimpleSpan struct {
	name      string
	startTime time.Time
	logger    *zap.Logger
}

func (s *SimpleSpan) End() {
	duration := time.Since(s.startTime)
	s.logger.Debug("Span ended",
		zap.String("span", s.name),
		zap.Duration("duration", duration))
}

func (s *SimpleSpan) SetName(name string) {
	s.name = name
}

func (s *SimpleSpan) SetAttribute(key, value string) {
	// Simplified - just log
}

// NewSimpleTracing creates a simple tracing provider
func NewSimpleTracing(serviceName string, logger *zap.Logger) *SimpleTracingProvider {
	return &SimpleTracingProvider{
		ServiceName: serviceName,
		logger:      logger,
		enabled:     true,
	}
}

func (t *SimpleTracingProvider) StartSpan(ctx context.Context, name string) (context.Context, *SimpleSpan) {
	span := &SimpleSpan{
		name:      name,
		startTime: time.Now(),
		logger:    t.logger,
	}
	t.logger.Debug("Span started", zap.String("span", name))
	return ctx, span
}

func (t *SimpleTracingProvider) Shutdown(ctx context.Context) error {
	return nil
}

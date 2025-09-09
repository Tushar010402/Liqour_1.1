package monitoring

import (
	"context"
	"io"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/opentracing/opentracing-go"
	"github.com/opentracing/opentracing-go/ext"
	"github.com/uber/jaeger-client-go"
	"github.com/uber/jaeger-client-go/config"
	"github.com/uber/jaeger-client-go/log"
	"github.com/uber/jaeger-client-go/metrics"
	"go.uber.org/zap"
)

var tracer opentracing.Tracer
var closer io.Closer

// InitTracing initializes Jaeger tracing
func InitTracing(serviceName string, jaegerEndpoint string) error {
	cfg := config.Configuration{
		ServiceName: serviceName,
		Sampler: &config.SamplerConfig{
			Type:  jaeger.SamplerTypeConst,
			Param: 1, // Sample 100% of traces
		},
		Reporter: &config.ReporterConfig{
			LogSpans:            true,
			BufferFlushInterval: 1 * time.Second,
			LocalAgentHostPort:  jaegerEndpoint,
		},
	}

	jLogger := jaegerLogger{logger: zap.L()}
	jMetricsFactory := metrics.NullFactory

	var err error
	tracer, closer, err = cfg.NewTracer(
		config.Logger(jLogger),
		config.Metrics(jMetricsFactory),
	)
	if err != nil {
		return err
	}

	opentracing.SetGlobalTracer(tracer)
	return nil
}

// CloseTracing closes the tracer
func CloseTracing() error {
	if closer != nil {
		return closer.Close()
	}
	return nil
}

// TracingMiddleware adds distributed tracing to HTTP requests
func TracingMiddleware(serviceName string) gin.HandlerFunc {
	return gin.HandlerFunc(func(c *gin.Context) {
		spanCtx, _ := tracer.Extract(opentracing.HTTPHeaders, opentracing.HTTPHeadersCarrier(c.Request.Header))
		
		span := tracer.StartSpan(
			c.Request.Method+" "+c.FullPath(),
			ext.RPCServerOption(spanCtx),
		)
		defer span.Finish()

		// Set standard tags
		ext.HTTPMethod.Set(span, c.Request.Method)
		ext.HTTPUrl.Set(span, c.Request.URL.String())
		ext.Component.Set(span, serviceName)

		// Add custom tags
		span.SetTag("service.name", serviceName)
		span.SetTag("http.path", c.FullPath())
		span.SetTag("user_agent", c.Request.UserAgent())
		
		// Extract user context if available
		if userID := c.GetString("user_id"); userID != "" {
			span.SetTag("user.id", userID)
		}
		if tenantID := c.GetString("tenant_id"); tenantID != "" {
			span.SetTag("tenant.id", tenantID)
		}

		// Store span in context
		ctx := opentracing.ContextWithSpan(c.Request.Context(), span)
		c.Request = c.Request.WithContext(ctx)

		c.Next()

		// Set response tags
		ext.HTTPStatusCode.Set(span, uint16(c.Writer.Status()))
		if c.Writer.Status() >= 400 {
			ext.Error.Set(span, true)
		}
	})
}

// StartSpan starts a new span from context
func StartSpan(ctx context.Context, operationName string) (opentracing.Span, context.Context) {
	span, ctx := opentracing.StartSpanFromContext(ctx, operationName)
	return span, ctx
}

// StartDBSpan starts a database operation span
func StartDBSpan(ctx context.Context, operation, table string) opentracing.Span {
	span, _ := opentracing.StartSpanFromContext(ctx, "db."+operation)
	ext.DBType.Set(span, "postgresql")
	ext.DBStatement.Set(span, operation)
	span.SetTag("db.table", table)
	return span
}

// StartRedisSpan starts a Redis operation span
func StartRedisSpan(ctx context.Context, operation string) opentracing.Span {
	span, _ := opentracing.StartSpanFromContext(ctx, "redis."+operation)
	ext.DBType.Set(span, "redis")
	ext.DBStatement.Set(span, operation)
	return span
}

// LogError logs an error to the span
func LogError(span opentracing.Span, err error) {
	if err != nil {
		ext.Error.Set(span, true)
		span.LogFields(
			opentracing.LogError(err),
		)
	}
}

// Custom Jaeger logger to integrate with Zap
type jaegerLogger struct {
	logger *zap.Logger
}

func (l jaegerLogger) Error(msg string) {
	l.logger.Error(msg)
}

func (l jaegerLogger) Infof(msg string, args ...interface{}) {
	l.logger.Sugar().Infof(msg, args...)
}

// GetTraceID gets the trace ID from context
func GetTraceID(ctx context.Context) string {
	if span := opentracing.SpanFromContext(ctx); span != nil {
		if jaegerSpan, ok := span.Context().(jaeger.SpanContext); ok {
			return jaegerSpan.TraceID().String()
		}
	}
	return ""
}

// AddSpanTags adds multiple tags to span
func AddSpanTags(span opentracing.Span, tags map[string]interface{}) {
	for key, value := range tags {
		span.SetTag(key, value)
	}
}

// TraceFunction traces a function execution
func TraceFunction(ctx context.Context, functionName string) (opentracing.Span, func()) {
	span, _ := opentracing.StartSpanFromContext(ctx, functionName)
	return span, func() {
		span.Finish()
	}
}
# Monitoring & Observability Guide

**Production Monitoring and Observability for OCR Systems**

**Reading Time**: 20 minutes
**Last Updated**: January 15, 2025
**Difficulty**: Intermediate to Advanced

---

## Table of Contents

1. [Observability Principles](#observability-principles)
2. [Key Metrics](#key-metrics)
3. [Logging Strategy](#logging-strategy)
4. [Distributed Tracing](#distributed-tracing)
5. [Alerting](#alerting)
6. [Dashboards](#dashboards)
7. [Health Checks](#health-checks)
8. [Performance Monitoring](#performance-monitoring)
9. [Error Tracking](#error-tracking)
10. [Capacity Planning](#capacity-planning)
11. [Monitoring Tools](#monitoring-tools)
12. [Incident Response](#incident-response)

---

## Observability Principles

### The Three Pillars

**1. Metrics** - Numerical measurements over time
**2. Logs** - Timestamped records of events
**3. Traces** - Request flow through system

### Golden Signals

Monitor these four signals for any service:

1. **Latency** - How long requests take
2. **Traffic** - How many requests
3. **Errors** - How many requests fail
4. **Saturation** - How full the service is

---

## Key Metrics

### OCR-Specific Metrics

```go
type OCRMetrics struct {
    // Success Metrics
    TotalRequests     int64   `json:"total_requests"`
    SuccessfulOCR     int64   `json:"successful_ocr"`
    FailedOCR         int64   `json:"failed_ocr"`
    SuccessRate       float64 `json:"success_rate"`

    // Field Extraction Rates
    SizeExtracted     int64   `json:"size_extracted"`
    BrandExtracted    int64   `json:"brand_extracted"`
    PriceExtracted    int64   `json:"price_extracted"`
    CategoryExtracted int64   `json:"category_extracted"`

    // Performance Metrics
    AvgProcessingTime time.Duration `json:"avg_processing_time"`
    P50ProcessingTime time.Duration `json:"p50_processing_time"`
    P95ProcessingTime time.Duration `json:"p95_processing_time"`
    P99ProcessingTime time.Duration `json:"p99_processing_time"`

    // Cache Metrics
    CacheHits   int64   `json:"cache_hits"`
    CacheMisses int64   `json:"cache_misses"`
    CacheHitRate float64 `json:"cache_hit_rate"`

    // API Metrics
    VisionAPICallsint64        `json:"vision_api_calls"`
    VisionAPIErrors     int64        `json:"vision_api_errors"`
    VisionAPIAvgLatency time.Duration `json:"vision_api_avg_latency"`

    GeminiAPICalls      int64        `json:"gemini_api_calls"`
    GeminiAPIErrors     int64        `json:"gemini_api_errors"`
    GeminiAPIAvgLatency time.Duration `json:"gemini_api_avg_latency"`

    // Quality Metrics
    ConfidenceScoreAvg  float64 `json:"confidence_score_avg"`
    ValidationFailures  int64   `json:"validation_failures"`
    ManualReviewFlagged int64   `json:"manual_review_flagged"`
}
```

### Implementing Metrics Collection

```go
type MetricsCollector struct {
    metrics     OCRMetrics
    mutex       sync.RWMutex
    timeSeries  []MetricsSnapshot
}

type MetricsSnapshot struct {
    Timestamp time.Time
    Metrics   OCRMetrics
}

func (mc *MetricsCollector) RecordOCRRequest(success bool, duration time.Duration) {
    mc.mutex.Lock()
    defer mc.mutex.Unlock()

    mc.metrics.TotalRequests++

    if success {
        mc.metrics.SuccessfulOCR++
    } else {
        mc.metrics.FailedOCR++
    }

    // Update processing time
    mc.updateProcessingTime(duration)

    // Calculate success rate
    mc.metrics.SuccessRate = float64(mc.metrics.SuccessfulOCR) /
                              float64(mc.metrics.TotalRequests) * 100
}

func (mc *MetricsCollector) RecordCacheAccess(hit bool) {
    mc.mutex.Lock()
    defer mc.mutex.Unlock()

    if hit {
        mc.metrics.CacheHits++
    } else {
        mc.metrics.CacheMisses++
    }

    total := mc.metrics.CacheHits + mc.metrics.CacheMisses
    if total > 0 {
        mc.metrics.CacheHitRate = float64(mc.metrics.CacheHits) /
                                   float64(total) * 100
    }
}

func (mc *MetricsCollector) RecordFieldExtraction(field string, extracted bool) {
    mc.mutex.Lock()
    defer mc.mutex.Unlock()

    if !extracted {
        return
    }

    switch field {
    case "size":
        mc.metrics.SizeExtracted++
    case "brand":
        mc.metrics.BrandExtracted++
    case "price":
        mc.metrics.PriceExtracted++
    case "category":
        mc.metrics.CategoryExtracted++
    }
}

func (mc *MetricsCollector) GetMetrics() OCRMetrics {
    mc.mutex.RLock()
    defer mc.mutex.RUnlock()
    return mc.metrics
}

// Expose metrics endpoint
func MetricsHandler(w http.ResponseWriter, r *http.Request) {
    metrics := globalMetricsCollector.GetMetrics()

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(metrics)
}
```

### Metrics Endpoint

```go
// Register metrics endpoint
http.HandleFunc("/metrics", MetricsHandler)

// Example response:
// GET /metrics
{
  "total_requests": 10000,
  "successful_ocr": 9523,
  "failed_ocr": 477,
  "success_rate": 95.23,
  "size_extracted": 9100,
  "brand_extracted": 9200,
  "price_extracted": 9150,
  "avg_processing_time": "1.2s",
  "p95_processing_time": "2.1s",
  "cache_hit_rate": 73.5,
  "vision_api_calls": 2650,
  "vision_api_errors": 12,
  "gemini_api_calls": 9100,
  "gemini_api_errors": 8
}
```

---

## Logging Strategy

### Log Levels

Use structured logging with appropriate levels:

```go
// Log levels (from most to least verbose)
const (
    DEBUG = "debug"   // Detailed diagnostic info
    INFO  = "info"    // General informational messages
    WARN  = "warn"    // Warning messages
    ERROR = "error"   // Error messages
    FATAL = "fatal"   // Critical errors
)
```

### Structured Logging

```go
import "github.com/sirupsen/logrus"

var log = logrus.New()

func init() {
    // Use JSON formatter for production
    log.SetFormatter(&logrus.JSONFormatter{})

    // Set log level from environment
    level, _ := logrus.ParseLevel(os.Getenv("LOG_LEVEL"))
    log.SetLevel(level)
}

// Example usage
func processOCR(imageData []byte) (*OCRResult, error) {
    startTime := time.Now()

    log.WithFields(logrus.Fields{
        "image_size": len(imageData),
        "request_id": getRequestID(),
    }).Info("Starting OCR processing")

    result, err := extractOCR(imageData)
    duration := time.Since(startTime)

    if err != nil {
        log.WithFields(logrus.Fields{
            "error":      err.Error(),
            "duration":   duration,
            "request_id": getRequestID(),
        }).Error("OCR processing failed")
        return nil, err
    }

    log.WithFields(logrus.Fields{
        "duration":   duration,
        "size":       result.Size,
        "brand":      result.BrandName,
        "confidence": result.Confidence,
        "request_id": getRequestID(),
    }).Info("OCR processing completed successfully")

    return result, nil
}
```

### Log Output Example

```json
{
  "level": "info",
  "msg": "OCR processing completed successfully",
  "duration": "1.234s",
  "size": "750ml",
  "brand": "Grey Goose",
  "confidence": 0.95,
  "request_id": "req-12345",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

### What to Log

**Always Log**:
- Request/response (with request ID)
- Errors and exceptions
- External API calls
- Cache hits/misses
- Performance metrics
- Security events (auth failures, etc.)

**Never Log**:
- Sensitive data (API keys, credentials)
- Full image data (log size/hash instead)
- Personal information (PII)
- Passwords or tokens

### Log Sampling for High Traffic

```go
type SamplingLogger struct {
    logger     *logrus.Logger
    sampleRate float64
}

func (sl *SamplingLogger) Info(msg string, fields logrus.Fields) {
    if rand.Float64() < sl.sampleRate {
        sl.logger.WithFields(fields).Info(msg)
    }
}

// Sample 10% of INFO logs, 100% of ERROR logs
func logWithSampling(level, msg string, fields logrus.Fields) {
    switch level {
    case "info":
        samplingLogger.Info(msg, fields)  // 10% sampled
    case "error":
        log.WithFields(fields).Error(msg)  // 100% logged
    }
}
```

---

## Distributed Tracing

### OpenTelemetry Integration

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/trace"
)

var tracer = otel.Tracer("ocr-service")

func processOCRWithTracing(ctx context.Context, imageData []byte) (*OCRResult, error) {
    ctx, span := tracer.Start(ctx, "processOCR")
    defer span.End()

    span.SetAttributes(
        attribute.Int("image_size", len(imageData)),
    )

    // Step 1: Vision API call
    text, err := callVisionAPIWithTracing(ctx, imageData)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, "Vision API failed")
        return nil, err
    }

    // Step 2: Extract fields
    result, err := extractFieldsWithTracing(ctx, text)
    if err != nil {
        span.RecordError(err)
        return nil, err
    }

    // Step 3: Normalize brand
    result.BrandName, err = normalizeBrandWithTracing(ctx, result.BrandName)
    if err != nil {
        span.RecordError(err)
        return nil, err
    }

    span.SetStatus(codes.Ok, "OCR completed successfully")
    return result, nil
}

func callVisionAPIWithTracing(ctx context.Context, imageData []byte) (string, error) {
    ctx, span := tracer.Start(ctx, "callVisionAPI")
    defer span.End()

    text, err := visionClient.DetectText(ctx, imageData)

    span.SetAttributes(
        attribute.Int("text_length", len(text)),
    )

    return text, err
}
```

### Trace Visualization

```
Request ID: req-12345
├─ processOCR (2.1s)
   ├─ callVisionAPI (1.5s)
   ├─ extractFields (0.3s)
   │  ├─ extractSize (0.05s)
   │  ├─ extractBrand (0.10s)
   │  └─ extractPrice (0.05s)
   └─ normalizeBrand (0.3s)
      └─ callGeminiAPI (0.25s)
```

---

## Alerting

### Alert Rules

```yaml
# alerts.yml
groups:
  - name: ocr_alerts
    interval: 1m
    rules:
      # Success Rate Alert
      - alert: OCRSuccessRateLow
        expr: ocr_success_rate < 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "OCR success rate below 90%"
          description: "Current success rate: {{ $value }}%"

      # Error Rate Alert
      - alert: OCRErrorRateHigh
        expr: rate(ocr_errors_total[5m]) > 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High OCR error rate"

      # Performance Alert
      - alert: OCRProcessingTimeSlow
        expr: ocr_processing_time_p95 > 5000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "OCR processing time degraded"
          description: "P95 latency: {{ $value }}ms"

      # Cache Alert
      - alert: CacheHitRateLow
        expr: ocr_cache_hit_rate < 50
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Cache hit rate below 50%"

      # External API Alert
      - alert: VisionAPIErrorsHigh
        expr: rate(vision_api_errors[5m]) > 5
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Vision API experiencing high error rate"
```

### Alert Implementation

```go
type AlertManager struct {
    rules []AlertRule
    notifications chan Alert
}

type AlertRule struct {
    Name        string
    Condition   func(OCRMetrics) bool
    Severity    string
    Message     string
    Cooldown    time.Duration
    LastFired   time.Time
}

type Alert struct {
    Name      string
    Severity  string
    Message   string
    Timestamp time.Time
    Metrics   OCRMetrics
}

func (am *AlertManager) CheckAlerts(metrics OCRMetrics) {
    for i, rule := range am.rules {
        // Check cooldown
        if time.Since(rule.LastFired) < rule.Cooldown {
            continue
        }

        // Evaluate condition
        if rule.Condition(metrics) {
            alert := Alert{
                Name:      rule.Name,
                Severity:  rule.Severity,
                Message:   rule.Message,
                Timestamp: time.Now(),
                Metrics:   metrics,
            }

            am.notifications <- alert
            am.rules[i].LastFired = time.Now()
        }
    }
}

// Example alert rules
var alertRules = []AlertRule{
    {
        Name:     "LowSuccessRate",
        Severity: "warning",
        Message:  "OCR success rate below 90%",
        Cooldown: 5 * time.Minute,
        Condition: func(m OCRMetrics) bool {
            return m.SuccessRate < 90.0
        },
    },
    {
        Name:     "HighLatency",
        Severity: "warning",
        Message:  "P95 latency above 5 seconds",
        Cooldown: 10 * time.Minute,
        Condition: func(m OCRMetrics) bool {
            return m.P95ProcessingTime > 5*time.Second
        },
    },
    {
        Name:     "LowCacheHitRate",
        Severity: "info",
        Message:  "Cache hit rate below 50%",
        Cooldown: 15 * time.Minute,
        Condition: func(m OCRMetrics) bool {
            return m.CacheHitRate < 50.0
        },
    },
}

// Send alerts
func (am *AlertManager) ProcessAlerts() {
    for alert := range am.notifications {
        switch alert.Severity {
        case "critical":
            sendPagerDutyAlert(alert)
            sendSlackAlert(alert)
            sendEmailAlert(alert)
        case "warning":
            sendSlackAlert(alert)
        case "info":
            logAlert(alert)
        }
    }
}
```

### Alert Channels

```go
// Slack notifications
func sendSlackAlert(alert Alert) {
    message := fmt.Sprintf(
        "*%s Alert: %s*\n%s\nSuccess Rate: %.2f%%\nP95 Latency: %v",
        alert.Severity,
        alert.Name,
        alert.Message,
        alert.Metrics.SuccessRate,
        alert.Metrics.P95ProcessingTime,
    )

    slackClient.PostMessage(webhookURL, message)
}

// Email notifications
func sendEmailAlert(alert Alert) {
    subject := fmt.Sprintf("[%s] %s", alert.Severity, alert.Name)
    body := fmt.Sprintf(`
Alert: %s
Severity: %s
Time: %s

Metrics:
- Success Rate: %.2f%%
- Total Requests: %d
- Failed Requests: %d
- P95 Latency: %v
- Cache Hit Rate: %.2f%%
`,
        alert.Name,
        alert.Severity,
        alert.Timestamp,
        alert.Metrics.SuccessRate,
        alert.Metrics.TotalRequests,
        alert.Metrics.FailedOCR,
        alert.Metrics.P95ProcessingTime,
        alert.Metrics.CacheHitRate,
    )

    emailClient.Send(oncallEmail, subject, body)
}
```

---

## Dashboards

### Grafana Dashboard JSON

```json
{
  "dashboard": {
    "title": "OCR Service Monitoring",
    "panels": [
      {
        "title": "OCR Success Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "ocr_success_rate",
            "legendFormat": "Success Rate %"
          }
        ],
        "yaxes": [
          {"format": "percent", "min": 0, "max": 100}
        ]
      },
      {
        "title": "Requests Per Second",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(ocr_requests_total[1m])",
            "legendFormat": "Requests/sec"
          }
        ]
      },
      {
        "title": "Processing Time (P95)",
        "type": "graph",
        "targets": [
          {
            "expr": "ocr_processing_time_p95",
            "legendFormat": "P95 Latency"
          }
        ],
        "yaxes": [
          {"format": "ms"}
        ]
      },
      {
        "title": "Cache Hit Rate",
        "type": "singlestat",
        "targets": [
          {
            "expr": "ocr_cache_hit_rate"
          }
        ],
        "format": "percent",
        "thresholds": "50,70"
      },
      {
        "title": "Field Extraction Rates",
        "type": "graph",
        "targets": [
          {"expr": "ocr_size_extraction_rate", "legendFormat": "Size"},
          {"expr": "ocr_brand_extraction_rate", "legendFormat": "Brand"},
          {"expr": "ocr_price_extraction_rate", "legendFormat": "Price"}
        ]
      },
      {
        "title": "External API Latency",
        "type": "graph",
        "targets": [
          {"expr": "vision_api_latency_avg", "legendFormat": "Vision API"},
          {"expr": "gemini_api_latency_avg", "legendFormat": "Gemini API"}
        ]
      }
    ]
  }
}
```

### Dashboard Panels

**Panel 1: Success Rate**
- Current success rate
- Target: >95%
- Threshold warnings at <90%

**Panel 2: Throughput**
- Requests per second
- Peak vs average
- Trend over time

**Panel 3: Latency**
- P50, P95, P99 percentiles
- Target: P95 <2s

**Panel 4: Cache Performance**
- Hit rate
- Eviction rate
- Memory usage

**Panel 5: Error Breakdown**
- Vision API errors
- Gemini API errors
- Validation failures
- Unknown errors

**Panel 6: Resource Usage**
- CPU utilization
- Memory usage
- Network I/O
- Disk I/O

---

## Health Checks

### Readiness & Liveness Probes

```go
// Liveness probe - Is the service alive?
func LivenessHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    json.NewEncoder(w).Encode(map[string]string{
        "status": "alive",
        "time":   time.Now().Format(time.RFC3339),
    })
}

// Readiness probe - Can the service handle requests?
func ReadinessHandler(w http.ResponseWriter, r *http.Request) {
    checks := []HealthCheck{
        checkRedisConnection(),
        checkDatabaseConnection(),
        checkVisionAPI(),
        checkGeminiAPI(),
    }

    allHealthy := true
    for _, check := range checks {
        if !check.Healthy {
            allHealthy = false
            break
        }
    }

    status := http.StatusOK
    if !allHealthy {
        status = http.StatusServiceUnavailable
    }

    w.WriteHeader(status)
    json.NewEncoder(w).Encode(map[string]interface{}{
        "status": allHealthy,
        "checks": checks,
        "time":   time.Now(),
    })
}

type HealthCheck struct {
    Name    string `json:"name"`
    Healthy bool   `json:"healthy"`
    Message string `json:"message,omitempty"`
    Latency string `json:"latency,omitempty"`
}

func checkRedisConnection() HealthCheck {
    start := time.Now()
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()

    _, err := redisClient.Ping(ctx).Result()
    latency := time.Since(start)

    if err != nil {
        return HealthCheck{
            Name:    "redis",
            Healthy: false,
            Message: err.Error(),
            Latency: latency.String(),
        }
    }

    return HealthCheck{
        Name:    "redis",
        Healthy: true,
        Latency: latency.String(),
    }
}

func checkVisionAPI() HealthCheck {
    start := time.Now()

    // Test with a minimal request
    _, err := visionClient.DetectText(context.Background(), dummyImage)
    latency := time.Since(start)

    return HealthCheck{
        Name:    "vision_api",
        Healthy: err == nil,
        Message: getErrorMessage(err),
        Latency: latency.String(),
    }
}
```

### Kubernetes Health Check Configuration

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: ocr-service
      image: liquorpro/sales:latest
      livenessProbe:
        httpGet:
          path: /health/live
          port: 8092
        initialDelaySeconds: 30
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 3

      readinessProbe:
        httpGet:
          path: /health/ready
          port: 8092
        initialDelaySeconds: 10
        periodSeconds: 5
        timeoutSeconds: 3
        failureThreshold: 3
```

---

## Performance Monitoring

### CPU & Memory Profiling

```go
import _ "net/http/pprof"

func main() {
    // Enable pprof
    go func() {
        log.Println(http.ListenAndServe("localhost:6060", nil))
    }()

    // Rest of application
}

// Access profiles:
// http://localhost:6060/debug/pprof/
// http://localhost:6060/debug/pprof/heap
// http://localhost:6060/debug/pprof/goroutine
```

### Profiling Commands

```bash
# CPU profile (30 seconds)
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30

# Heap profile
go tool pprof http://localhost:6060/debug/pprof/heap

# Goroutine profile
go tool pprof http://localhost:6060/debug/pprof/goroutine

# Block profile
go tool pprof http://localhost:6060/debug/pprof/block
```

### Resource Usage Monitoring

```go
func monitorResourceUsage() {
    ticker := time.NewTicker(1 * time.Minute)

    for range ticker.C {
        var m runtime.MemStats
        runtime.ReadMemStats(&m)

        log.WithFields(logrus.Fields{
            "alloc_mb":       m.Alloc / 1024 / 1024,
            "total_alloc_mb": m.TotalAlloc / 1024 / 1024,
            "sys_mb":         m.Sys / 1024 / 1024,
            "num_gc":         m.NumGC,
            "goroutines":     runtime.NumGoroutine(),
        }).Info("Resource usage")

        // Alert if memory usage is high
        if m.Alloc > 500*1024*1024 {  // >500MB
            log.Warn("High memory usage detected")
        }
    }
}
```

---

## Error Tracking

### Error Categorization

```go
type ErrorCategory string

const (
    ErrorCategoryVisionAPI     ErrorCategory = "vision_api"
    ErrorCategoryGeminiAPI     ErrorCategory = "gemini_api"
    ErrorCategoryValidation    ErrorCategory = "validation"
    ErrorCategoryCache         ErrorCategory = "cache"
    ErrorCategoryDatabase      ErrorCategory = "database"
    ErrorCategoryUnknown       ErrorCategory = "unknown"
)

type ErrorTracker struct {
    errors map[ErrorCategory]int64
    mutex  sync.RWMutex
}

func (et *ErrorTracker) RecordError(category ErrorCategory, err error) {
    et.mutex.Lock()
    defer et.mutex.Unlock()

    et.errors[category]++

    log.WithFields(logrus.Fields{
        "category": category,
        "error":    err.Error(),
    }).Error("Error recorded")
}

func (et *ErrorTracker) GetErrorCounts() map[ErrorCategory]int64 {
    et.mutex.RLock()
    defer et.mutex.RUnlock()

    counts := make(map[ErrorCategory]int64)
    for k, v := range et.errors {
        counts[k] = v
    }
    return counts
}
```

### Error Rate Calculation

```go
func calculateErrorRate(window time.Duration) float64 {
    recentErrors := getErrorsInWindow(window)
    recentTotal := getRequestsInWindow(window)

    if recentTotal == 0 {
        return 0
    }

    return float64(recentErrors) / float64(recentTotal) * 100
}
```

---

## Capacity Planning

### Key Metrics for Capacity

```go
type CapacityMetrics struct {
    CurrentRPS     float64       // Current requests per second
    PeakRPS        float64       // Peak RPS in last 24h
    AvgProcessingTime time.Duration
    ResourceUtilization struct {
        CPU    float64  // Percentage
        Memory float64  // Percentage
        Disk   float64  // Percentage
    }
    GrowthRate     float64       // % increase per month
}

func calculateCapacityHeadroom() float64 {
    metrics := getCurrentCapacityMetrics()

    // Maximum sustainable RPS based on resources
    maxRPS := calculateMaxRPS(metrics)

    // Current RPS
    currentRPS := metrics.CurrentRPS

    // Headroom percentage
    headroom := (maxRPS - currentRPS) / maxRPS * 100

    return headroom
}

func predictCapacityNeeds(months int) CapacityMetrics {
    current := getCurrentCapacityMetrics()

    // Project growth
    growthMultiplier := math.Pow(1+current.GrowthRate/100, float64(months))

    return CapacityMetrics{
        CurrentRPS: current.CurrentRPS * growthMultiplier,
        // ... other projected metrics
    }
}
```

---

## Monitoring Tools

### Recommended Stack

1. **Metrics**: Prometheus + Grafana
2. **Logging**: ELK Stack (Elasticsearch, Logstash, Kibana) or Loki
3. **Tracing**: Jaeger or Zipkin
4. **Alerting**: AlertManager + PagerDuty
5. **APM**: New Relic or Datadog (optional)

### Quick Setup Commands

```bash
# Prometheus
docker run -d -p 9090:9090 \
  -v /path/to/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus

# Grafana
docker run -d -p 3000:3000 grafana/grafana

# Jaeger (all-in-one)
docker run -d -p 16686:16686 -p 14268:14268 jaegertracing/all-in-one
```

---

## Incident Response

### Monitoring During Incidents

```bash
# Real-time metrics
./scripts/ocr_metrics_monitor.sh 5

# Real-time logs with filtering
sudo docker logs -f liquorpro-sales-prod | grep -i error

# Watch resource usage
watch -n 2 'docker stats liquorpro-sales-prod --no-stream'

# Check recent errors
sudo docker logs liquorpro-sales-prod --since 5m | grep -i error | wc -l
```

### Post-Incident Analysis

```bash
# Generate incident report
./scripts/generate_incident_report.sh <start_time> <end_time>

# Analyze error patterns
sudo docker logs liquorpro-sales-prod --since <start_time> --until <end_time> \
  | grep -i error | sort | uniq -c | sort -rn

# Check metric trends
curl http://localhost:8092/metrics?from=<start>&to=<end>
```

---

## Monitoring Checklist

### Daily Checks
- [ ] Review dashboard for anomalies
- [ ] Check success rate (target >95%)
- [ ] Verify cache hit rate (target >70%)
- [ ] Review error logs
- [ ] Check resource utilization

### Weekly Checks
- [ ] Analyze performance trends
- [ ] Review alert frequency
- [ ] Check capacity headroom
- [ ] Audit log volume and retention
- [ ] Update dashboards if needed

### Monthly Checks
- [ ] Capacity planning review
- [ ] Alert rule effectiveness
- [ ] Dashboard optimization
- [ ] Log retention policy review
- [ ] Monitoring cost optimization

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0
**Maintained by**: OCR Development Team

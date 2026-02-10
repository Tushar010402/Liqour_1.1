# Monitoring Guide

## Overview

Monitor LiquorPro with Prometheus, Grafana, and structured logging.

---

## 1. Metrics Endpoint

All services expose metrics at `/metrics`:

```bash
curl http://localhost:8090/metrics
```

---

## 2. Key Metrics

### HTTP Metrics
- `http_requests_total` - Total requests
- `http_request_duration_seconds` - Request latency
- `http_request_size_bytes` - Request size
- `http_response_size_bytes` - Response size

### Database Metrics
- `db_connections_active` - Active connections
- `db_query_duration_seconds` - Query latency

### Business Metrics
- `sales_records_total` - Total sales records
- `ocr_processing_duration_seconds` - OCR time
- `collection_deadline_compliance` - Deadline compliance rate

---

## 3. Prometheus Setup

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'liquorpro'
    static_configs:
      - targets:
        - gateway:8090
        - auth:8091
        - sales:8092
        - inventory:8093
        - finance:8094
    metrics_path: /metrics
```

---

## 4. Grafana Dashboards

Import dashboards for:
- Service health overview
- Request latency
- Error rates
- Database performance
- Business metrics

---

## 5. Alerting

```yaml
# Alert rules
groups:
  - name: liquorpro
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
        for: 5m
        labels:
          severity: critical

      - alert: HighLatency
        expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 2
        for: 5m
        labels:
          severity: warning
```

---

## 6. Logging

### Log Format
```json
{
  "level": "info",
  "timestamp": "2025-01-11T10:00:00Z",
  "request_id": "uuid",
  "service": "gateway",
  "message": "Request completed",
  "duration_ms": 45,
  "status": 200
}
```

### Log Aggregation
Use Loki or Elasticsearch for log aggregation.

---

## 7. Health Checks

```bash
# Liveness
curl http://localhost:8090/health/live

# Readiness
curl http://localhost:8090/health/ready

# Full health
curl http://localhost:8090/health
```

---

## 8. Tracing

Jaeger integration for distributed tracing:

```yaml
tracing:
  enabled: true
  jaeger:
    agent_host: jaeger-agent
    agent_port: 6831
```

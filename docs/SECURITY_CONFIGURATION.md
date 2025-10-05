# Security Configuration Guide

## Overview

This document describes the security enhancements implemented for the Brand Onboarding system, including security headers, advanced rate limiting, and configuration recommendations.

## Security Headers

### Implementation

Security headers are implemented in `pkg/shared/middleware/security_headers.go`

### Headers Applied

#### 1. **X-Frame-Options**
```
Value: DENY
Purpose: Prevents clickjacking attacks by disallowing page embedding
```

#### 2. **X-Content-Type-Options**
```
Value: nosniff
Purpose: Prevents MIME type sniffing attacks
```

#### 3. **X-XSS-Protection**
```
Value: 1; mode=block
Purpose: Enables browser XSS filtering
```

#### 4. **Strict-Transport-Security (Production Only)**
```
Value: max-age=31536000; includeSubDomains; preload
Purpose: Enforces HTTPS for 1 year
```

#### 5. **Content-Security-Policy**
```
Policy:
- default-src 'self'
- script-src 'self' 'unsafe-inline' 'unsafe-eval'
- style-src 'self' 'unsafe-inline'
- img-src 'self' data: https:
- frame-ancestors 'none'
- base-uri 'self'
- form-action 'self'

Purpose: Restricts resource loading sources
```

#### 6. **Referrer-Policy**
```
Value: strict-origin-when-cross-origin
Purpose: Controls referrer information disclosure
```

#### 7. **Permissions-Policy**
```
Disabled Features:
- geolocation, microphone, camera
- payment, usb
- magnetometer, gyroscope, accelerometer

Purpose: Restricts browser feature access
```

#### 8. **Cache-Control**
```
Value: no-store, no-cache, must-revalidate, private
Purpose: Prevents caching of sensitive data
Exception: /health and /metrics endpoints
```

### Usage

```go
// In routes setup
router.Use(middleware.SecurityHeaders())

// Or for API-specific headers
api.Use(middleware.APISecurityHeaders())
```

---

## Advanced Rate Limiting

### Implementation

Rate limiting is implemented in `pkg/shared/middleware/advanced_rate_limit.go`

### Architecture

- **Algorithm**: Token Bucket with Redis
- **Granularity**: Per tenant, per user, or per IP
- **Distribution**: Redis-based for multi-instance deployments

### Rate Limit Tiers

#### 1. **Brand Onboarding**
```go
RequestsPerMinute: 10
BurstSize: 3
Purpose: Prevent abuse of onboarding process
```

#### 2. **Brand Listing**
```go
RequestsPerMinute: 60
BurstSize: 10
Purpose: Allow reasonable browsing while preventing scraping
```

#### 3. **Tiered Limits by Subscription**

| Tier | Requests/Min | Burst | Use Case |
|------|--------------|-------|----------|
| Free | 30 | 5 | Basic usage |
| Premium | 100 | 20 | Power users |
| Enterprise | 500 | 100 | High volume |

### Configuration Examples

#### Basic Rate Limiting

```go
import (
    "github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// Create rate limiter
config := middleware.RateLimitConfig{
    RequestsPerMinute: 60,
    BurstSize: 10,
    KeyPrefix: "ratelimit:api",
    SkipPaths: []string{"/health", "/metrics"},
}

limiter := middleware.NewAdvancedRateLimiter(redisClient, config, logger)
router.Use(limiter.RateLimitMiddleware())
```

#### Tiered Rate Limiting

```go
// Configure tiers
tieredConfig := middleware.TieredRateLimitConfig{
    Free: middleware.RateLimitConfig{
        RequestsPerMinute: 30,
        BurstSize: 5,
        KeyPrefix: "ratelimit:free",
    },
    Premium: middleware.RateLimitConfig{
        RequestsPerMinute: 100,
        BurstSize: 20,
        KeyPrefix: "ratelimit:premium",
    },
    Enterprise: middleware.RateLimitConfig{
        RequestsPerMinute: 500,
        BurstSize: 100,
        KeyPrefix: "ratelimit:enterprise",
    },
}

tieredLimiter := middleware.NewTieredRateLimiter(redisClient, tieredConfig, logger)
router.Use(tieredLimiter.TieredRateLimitMiddleware())
```

#### Endpoint-Specific Limits

```go
// Different limits for different endpoints
limits := map[string]middleware.RateLimitConfig{
    "/api/inventory/saas-brands/onboard": middleware.BrandOnboardingRateLimitConfig(),
    "/api/inventory/saas-brands/available": middleware.BrandListingRateLimitConfig(),
}

defaultLimit := middleware.RateLimitConfig{
    RequestsPerMinute: 60,
    BurstSize: 10,
    KeyPrefix: "ratelimit:default",
}

endpointLimiter := middleware.NewEndpointRateLimiter(redisClient, limits, defaultLimit, logger)
router.Use(endpointLimiter.EndpointRateLimitMiddleware())
```

### Rate Limit Headers

All rate-limited responses include:

```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1696521600
Retry-After: 15
```

### Error Response

When rate limit is exceeded:

```json
{
  "error": "rate_limit_exceeded",
  "message": "Rate limit exceeded. Try again in 15 seconds",
  "retry_after": 15
}
```

HTTP Status: `429 Too Many Requests`

---

## Integration with Brand Onboarding

### Recommended Configuration

```go
// In internal/inventory/routes/routes.go

import (
    "github.com/liquorpro/go-backend/pkg/shared/middleware"
)

func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache,
                 redisClient *redis.Client, logger *zap.Logger) {

    // Apply security headers globally
    router.Use(middleware.SecurityHeaders())

    // ... auth middleware ...

    // Brand onboarding routes with specific rate limits
    brandOnboardLimiter := middleware.NewAdvancedRateLimiter(
        redisClient,
        middleware.BrandOnboardingRateLimitConfig(),
        logger,
    )

    inventory := api.Group("/inventory")
    {
        // Brand listing - higher limit
        brandListLimiter := middleware.NewAdvancedRateLimiter(
            redisClient,
            middleware.BrandListingRateLimitConfig(),
            logger,
        )

        inventory.GET("/saas-brands/available",
            brandListLimiter.RateLimitMiddleware(),
            inventoryHandlers.GetAvailableBrandTemplates,
        )

        // Brand onboarding - stricter limit
        inventory.POST("/saas-brands/onboard",
            brandOnboardLimiter.RateLimitMiddleware(),
            inventoryHandlers.OnboardBrands,
        )
    }
}
```

---

## Security Best Practices

### 1. **HTTPS Enforcement**

In production, ensure HTTPS is enforced:

```nginx
# Nginx configuration
server {
    listen 80;
    server_name liquorpro.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name liquorpro.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    # Strong SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://backend:8093;
    }
}
```

### 2. **Input Validation**

Always validate input before rate limiting:

```go
// Validate UUID format
if _, err := uuid.Parse(brandID); err != nil {
    c.JSON(400, gin.H{"error": "invalid brand ID format"})
    return
}

// Validate tenant ID
if tenantID := c.GetHeader("X-Tenant-ID"); tenantID == "" {
    c.JSON(401, gin.H{"error": "tenant ID required"})
    return
}
```

### 3. **Redis Security**

Secure Redis connection:

```yaml
# docker-compose.yml
redis:
  image: redis:7-alpine
  command: redis-server --requirepass ${REDIS_PASSWORD}
  ports:
    - "6379:6379"
  volumes:
    - redis_data:/data
```

```go
// In code
redisClient := redis.NewClient(&redis.Options{
    Addr:     "redis:6379",
    Password: os.Getenv("REDIS_PASSWORD"),
    DB:       0,
    TLSConfig: &tls.Config{
        MinVersion: tls.VersionTLS12,
    },
})
```

### 4. **Monitoring & Alerting**

Monitor rate limit violations:

```go
// In rate limiter
if !allowed {
    // Log rate limit violation
    logger.Warn("Rate limit exceeded",
        zap.String("identifier", identifier),
        zap.String("path", c.Request.URL.Path),
        zap.String("ip", c.ClientIP()),
    )

    // Increment Prometheus metric
    rateLimitExceededCounter.Inc()

    // ... return 429 response ...
}
```

---

## Testing Security Configuration

### 1. **Test Security Headers**

```bash
# Check security headers
curl -I https://api.liquorpro.com/api/inventory/saas-brands/available

# Should include:
# X-Frame-Options: DENY
# X-Content-Type-Options: nosniff
# X-XSS-Protection: 1; mode=block
# Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

### 2. **Test Rate Limiting**

```bash
# Test rate limit
for i in {1..100}; do
  curl -H "Authorization: Bearer $TOKEN" \
       -H "X-Tenant-ID: $TENANT_ID" \
       https://api.liquorpro.com/api/inventory/saas-brands/available \
       -w "\n%{http_code}\n" -o /dev/null
done

# Should see:
# 200, 200, 200, ... (up to limit)
# 429, 429, 429, ... (after limit)
```

### 3. **Security Scan**

```bash
# Run OWASP ZAP security scan
docker run -t owasp/zap2docker-stable zap-baseline.py \
  -t https://api.liquorpro.com \
  -r security_scan_report.html
```

---

## Production Deployment Checklist

- [ ] Enable HTTPS enforcement (Strict-Transport-Security header)
- [ ] Configure Redis with password authentication
- [ ] Set up rate limit monitoring alerts
- [ ] Test all security headers are present
- [ ] Verify rate limits under load
- [ ] Configure WAF rules (Cloudflare/AWS WAF)
- [ ] Enable DDoS protection
- [ ] Set up IP whitelisting for admin endpoints
- [ ] Review and adjust CSP policy for your domain
- [ ] Enable audit logging for security events

---

## Troubleshooting

### Rate Limit Not Working

1. **Check Redis connection**
   ```bash
   redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD ping
   # Should return: PONG
   ```

2. **Check rate limit keys**
   ```bash
   redis-cli -h localhost -a $REDIS_PASSWORD
   > KEYS ratelimit:*
   # Should show active rate limit keys
   ```

3. **Check middleware order**
   ```go
   // Rate limit must be BEFORE handler
   router.Use(authMiddleware)
   router.Use(rateLimitMiddleware)  // Before handler
   router.POST("/onboard", handler)
   ```

### Security Headers Missing

1. **Check middleware registration**
   ```go
   // Must be registered globally or per route
   router.Use(middleware.SecurityHeaders())
   ```

2. **Check for header overrides**
   ```go
   // Don't override security headers later
   // BAD: c.Header("X-Frame-Options", "ALLOW")
   ```

### Rate Limit Too Strict/Loose

1. **Adjust configuration**
   ```go
   // Increase for legitimate high-volume users
   config.RequestsPerMinute = 100
   config.BurstSize = 20
   ```

2. **Use tiered limits**
   ```go
   // Different limits for different subscription tiers
   tieredLimiter.TieredRateLimitMiddleware()
   ```

---

## Additional Resources

- [OWASP Security Headers](https://owasp.org/www-project-secure-headers/)
- [Rate Limiting Strategies](https://cloud.google.com/architecture/rate-limiting-strategies)
- [Redis Security](https://redis.io/docs/management/security/)
- [Content Security Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP)

---

**Last Updated:** October 5, 2025
**Version:** 1.0.0

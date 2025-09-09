package middleware

import (
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

// CORSMiddleware sets up CORS headers
func CORSMiddleware() gin.HandlerFunc {
	config := cors.DefaultConfig()
	config.AllowAllOrigins = false
	config.AllowOrigins = []string{
		"http://localhost:3000",  // React dev server
		"http://localhost:3001",  // Next.js dev server
		"http://localhost:8090",  // API Gateway
		"http://localhost:8095",  // Frontend service
	}
	config.AllowMethods = []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"}
	config.AllowHeaders = []string{
		"Origin",
		"Content-Type", 
		"Accept",
		"Authorization",
		"X-Request-ID",
		"X-Tenant-ID",
	}
	config.ExposeHeaders = []string{
		"X-Request-ID",
		"X-Total-Count",
	}
	config.AllowCredentials = true
	
	return cors.New(config)
}

// ProductionCORSMiddleware for production with stricter settings
func ProductionCORSMiddleware(allowedOrigins []string) gin.HandlerFunc {
	config := cors.DefaultConfig()
	config.AllowAllOrigins = false
	config.AllowOrigins = allowedOrigins
	config.AllowMethods = []string{"GET", "POST", "PUT", "PATCH", "DELETE"}
	config.AllowHeaders = []string{
		"Origin",
		"Content-Type", 
		"Accept",
		"Authorization",
		"X-Request-ID",
		"X-Tenant-ID",
	}
	config.ExposeHeaders = []string{
		"X-Request-ID",
		"X-Total-Count",
	}
	config.AllowCredentials = true
	
	return cors.New(config)
}
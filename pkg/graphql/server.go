package graphql

import (
	"time"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/pkg/observability"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// GraphQLServer manages the GraphQL server (simplified version)
type GraphQLServer struct {
	db      *gorm.DB
	redis   *redis.Client
	logger  *zap.Logger
	tracer  *observability.SimpleTracingProvider
	config  *GraphQLConfig
	enabled bool
}

// GraphQLConfig contains GraphQL server configuration
type GraphQLConfig struct {
	EnablePlayground    bool
	EnableIntrospection bool
	MaxComplexity       int
	MaxDepth            int
	QueryCacheTTL       time.Duration
	RateLimitPerMinute  int
	UploadMaxSize       int64
	WebSocketEnabled    bool
}

// NewGraphQLServer creates a new GraphQL server
func NewGraphQLServer(
	db *gorm.DB,
	redis *redis.Client,
	logger *zap.Logger,
	config *GraphQLConfig,
) (*GraphQLServer, error) {
	// Create simple tracer
	tracer := observability.NewSimpleTracing("graphql-server", logger)

	logger.Info("GraphQL server created (simplified mode)",
		zap.Bool("playground", config.EnablePlayground),
		zap.Bool("websocket", config.WebSocketEnabled))

	return &GraphQLServer{
		db:      db,
		redis:   redis,
		logger:  logger,
		tracer:  tracer,
		config:  config,
		enabled: true,
	}, nil
}

// RegisterRoutes registers GraphQL routes with Gin
func (s *GraphQLServer) RegisterRoutes(router *gin.RouterGroup) {
	// GraphQL endpoint
	router.POST("/graphql", s.graphqlHandler())
	router.GET("/graphql", s.graphqlHandler())

	// GraphQL Playground
	if s.config.EnablePlayground {
		router.GET("/playground", s.playgroundHandler())
	}

	s.logger.Info("GraphQL routes registered",
		zap.Bool("playground", s.config.EnablePlayground))
}

func (s *GraphQLServer) graphqlHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		_, span := s.tracer.StartSpan(c.Request.Context(), "graphql.query")
		defer span.End()

		// For now, return a simple response
		c.JSON(200, gin.H{
			"data": gin.H{
				"message": "GraphQL server is running",
				"version": "1.0.0",
				"note":    "Full schema implementation pending gqlgen code generation",
			},
		})

		s.logger.Debug("GraphQL query processed",
			zap.String("method", c.Request.Method))
	}
}

func (s *GraphQLServer) playgroundHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		html := `
<!DOCTYPE html>
<html>
<head>
    <title>GraphQL Playground</title>
    <style>
        body { margin: 0; padding: 20px; font-family: Arial, sans-serif; }
        h1 { color: #333; }
        .info { background: #f0f0f0; padding: 15px; border-radius: 5px; }
        code { background: #e0e0e0; padding: 2px 5px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>🚀 GraphQL Playground</h1>
    <div class="info">
        <h2>GraphQL Server is Running!</h2>
        <p>Endpoint: <code>/api/graphql</code></p>
        <p>Status: ✅ Active (Simplified Mode)</p>
        <p><strong>Note:</strong> Full GraphQL schema will be available after running <code>gqlgen generate</code></p>
        <h3>Quick Test:</h3>
        <pre>curl -X POST http://localhost:8090/api/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ __typename }"}'</pre>
    </div>
</body>
</html>`
		c.Header("Content-Type", "text/html")
		c.String(200, html)
	}
}

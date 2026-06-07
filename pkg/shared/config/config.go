package config

import (
	"fmt"
	"strings"

	"github.com/spf13/viper"
)

// Config holds all configuration for the application
type Config struct {
	Server   ServerConfig   `mapstructure:"server"`
	Database DatabaseConfig `mapstructure:"database"`
	Redis    RedisConfig    `mapstructure:"redis"`
	JWT      JWTConfig      `mapstructure:"jwt"`
	App      AppConfig      `mapstructure:"app"`
	Services ServicesConfig `mapstructure:"services"`
	Kafka    KafkaConfig    `mapstructure:"kafka"`
	GraphQL  GraphQLConfig  `mapstructure:"graphql"`
}

// ServerConfig holds server configuration
type ServerConfig struct {
	Host         string `mapstructure:"host"`
	Port         int    `mapstructure:"port"`
	Mode         string `mapstructure:"mode"` // debug, release, test
	ReadTimeout  int    `mapstructure:"read_timeout"`
	WriteTimeout int    `mapstructure:"write_timeout"`
	IdleTimeout  int    `mapstructure:"idle_timeout"`
}

// DatabaseConfig holds database configuration
type DatabaseConfig struct {
	Host     string `mapstructure:"host"`
	Port     int    `mapstructure:"port"`
	User     string `mapstructure:"user"`
	Password string `mapstructure:"password"`
	DBName   string `mapstructure:"dbname"`
	SSLMode  string `mapstructure:"sslmode"`
	TimeZone string `mapstructure:"timezone"`
}

// RedisConfig holds Redis configuration
type RedisConfig struct {
	Host     string `mapstructure:"host"`
	Port     int    `mapstructure:"port"`
	Password string `mapstructure:"password"`
	DB       int    `mapstructure:"db"`
}

// JWTConfig holds JWT configuration
type JWTConfig struct {
	Secret          string `mapstructure:"secret"`
	ExpirationHours int    `mapstructure:"expiration_hours"`
	RefreshHours    int    `mapstructure:"refresh_hours"`
	Issuer          string `mapstructure:"issuer"`
}

// AppConfig holds application configuration
type AppConfig struct {
	Name        string `mapstructure:"name"`
	Version     string `mapstructure:"version"`
	Environment string `mapstructure:"environment"`
	Debug       bool   `mapstructure:"debug"`
	LogLevel    string `mapstructure:"log_level"`
}

// ServicesConfig holds microservices configuration
type ServicesConfig struct {
	Gateway   ServiceConfig `mapstructure:"gateway"`
	Auth      ServiceConfig `mapstructure:"auth"`
	Sales     ServiceConfig `mapstructure:"sales"`
	Inventory ServiceConfig `mapstructure:"inventory"`
	Finance   ServiceConfig `mapstructure:"finance"`
}

// ServiceConfig holds individual service configuration
type ServiceConfig struct {
	Host string `mapstructure:"host"`
	Port int    `mapstructure:"port"`
	URL  string `mapstructure:"url"`
}

// KafkaConfig holds Kafka configuration
type KafkaConfig struct {
	Enabled       bool     `mapstructure:"enabled"`
	Brokers       []string `mapstructure:"brokers"`
	GroupID       string   `mapstructure:"group_id"`
	BatchSize     int      `mapstructure:"batch_size"`
	BatchTimeout  int      `mapstructure:"batch_timeout"`
	RetryAttempts int      `mapstructure:"retry_attempts"`
}

// GraphQLConfig holds GraphQL configuration
type GraphQLConfig struct {
	Enabled             bool   `mapstructure:"enabled"`
	EnablePlayground    bool   `mapstructure:"enable_playground"`
	EnableIntrospection bool   `mapstructure:"enable_introspection"`
	MaxComplexity       int    `mapstructure:"max_complexity"`
	MaxDepth            int    `mapstructure:"max_depth"`
	RateLimitPerMinute  int    `mapstructure:"rate_limit_per_minute"`
	WebSocketEnabled    bool   `mapstructure:"websocket_enabled"`
}

// LoadConfig loads configuration from file and environment variables
func LoadConfig(configPath string) (*Config, error) {
	viper.SetConfigName("config")
	viper.SetConfigType("yaml")
	viper.AddConfigPath(configPath)
	viper.AddConfigPath(".")
	viper.AddConfigPath("./config")

	// Set default values
	setDefaults()

	// Enable environment variables
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	// Bind specific environment variables to handle naming inconsistencies
	// This ensures DATABASE_NAME maps to database.dbname
	bindEnvVars()

	if err := viper.ReadInConfig(); err != nil {
		// Config file not found, use defaults and env vars
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, err
		}
	}

	var config Config
	if err := viper.Unmarshal(&config); err != nil {
		return nil, err
	}

	return &config, nil
}

// bindEnvVars explicitly binds environment variables to configuration keys
// This handles naming inconsistencies (e.g., DATABASE_NAME -> database.dbname)
func bindEnvVars() {
	// Database environment variables
	viper.BindEnv("database.host", "DATABASE_HOST")
	viper.BindEnv("database.port", "DATABASE_PORT")
	viper.BindEnv("database.user", "DATABASE_USER")
	viper.BindEnv("database.password", "DATABASE_PASSWORD")
	viper.BindEnv("database.dbname", "DATABASE_NAME") // Maps DATABASE_NAME to dbname
	viper.BindEnv("database.sslmode", "DATABASE_SSLMODE", "DATABASE_SSL_MODE")
	viper.BindEnv("database.timezone", "DATABASE_TIMEZONE", "DATABASE_TIME_ZONE")

	// Redis environment variables
	viper.BindEnv("redis.host", "REDIS_HOST")
	viper.BindEnv("redis.port", "REDIS_PORT")
	viper.BindEnv("redis.password", "REDIS_PASSWORD")
	viper.BindEnv("redis.db", "REDIS_DB")

	// JWT environment variables
	viper.BindEnv("jwt.secret", "JWT_SECRET")
	viper.BindEnv("jwt.expiration_hours", "JWT_EXPIRATION_HOURS")
	viper.BindEnv("jwt.refresh_hours", "JWT_REFRESH_HOURS")

	// App environment variables
	viper.BindEnv("app.environment", "APP_ENVIRONMENT")
	viper.BindEnv("app.debug", "APP_DEBUG")
	viper.BindEnv("app.log_level", "LOG_LEVEL")
}

// setDefaults sets default configuration values
func setDefaults() {
	// Server defaults
	viper.SetDefault("server.host", "0.0.0.0")
	viper.SetDefault("server.port", 8090)
	viper.SetDefault("server.mode", "debug")
	viper.SetDefault("server.read_timeout", 120)  // Increased for large OCR uploads
	viper.SetDefault("server.write_timeout", 120) // Increased for OCR processing
	viper.SetDefault("server.idle_timeout", 120)

	// Database defaults
	viper.SetDefault("database.host", "localhost")
	viper.SetDefault("database.port", 5432)
	viper.SetDefault("database.user", "liquorpro_prod")
	viper.SetDefault("database.password", "liquorpro_password")
	viper.SetDefault("database.dbname", "liquorpro_production")
	viper.SetDefault("database.sslmode", "disable")
	viper.SetDefault("database.timezone", "UTC")

	// Redis defaults
	viper.SetDefault("redis.host", "localhost")
	viper.SetDefault("redis.port", 6379)
	viper.SetDefault("redis.password", "")
	viper.SetDefault("redis.db", 0)

	// JWT defaults
	viper.SetDefault("jwt.secret", "your-secret-key")
	viper.SetDefault("jwt.expiration_hours", 168)  // 7 days — prevents frequent re-login
	viper.SetDefault("jwt.refresh_hours", 720)    // 30 days
	viper.SetDefault("jwt.issuer", "liquorpro")

	// App defaults
	viper.SetDefault("app.name", "LiquorPro")
	viper.SetDefault("app.version", "1.0.0")
	viper.SetDefault("app.environment", "development")
	viper.SetDefault("app.debug", true)
	viper.SetDefault("app.log_level", "info")

	// Services defaults
	viper.SetDefault("services.gateway.host", "0.0.0.0")
	viper.SetDefault("services.gateway.port", 8090)
	viper.SetDefault("services.gateway.url", "http://localhost:8090")
	viper.SetDefault("services.auth.host", "0.0.0.0")
	viper.SetDefault("services.auth.port", 8091)
	viper.SetDefault("services.auth.url", "http://localhost:8091")
	viper.SetDefault("services.sales.host", "0.0.0.0")
	viper.SetDefault("services.sales.port", 8092)
	viper.SetDefault("services.sales.url", "http://localhost:8092")
	viper.SetDefault("services.inventory.host", "0.0.0.0")
	viper.SetDefault("services.inventory.port", 8093)
	viper.SetDefault("services.inventory.url", "http://localhost:8093")
	viper.SetDefault("services.finance.host", "0.0.0.0")
	viper.SetDefault("services.finance.port", 8094)
	viper.SetDefault("services.finance.url", "http://localhost:8094")

	// Kafka defaults (optional, graceful degradation if not available)
	viper.SetDefault("kafka.enabled", false) // Disabled by default
	viper.SetDefault("kafka.brokers", []string{"localhost:9092"})
	viper.SetDefault("kafka.group_id", "liquorpro-group")
	viper.SetDefault("kafka.batch_size", 100)
	viper.SetDefault("kafka.batch_timeout", 1000)
	viper.SetDefault("kafka.retry_attempts", 3)

	// GraphQL defaults
	viper.SetDefault("graphql.enabled", true) // Enabled by default
	viper.SetDefault("graphql.enable_playground", true)
	viper.SetDefault("graphql.enable_introspection", true)
	viper.SetDefault("graphql.max_complexity", 1000)
	viper.SetDefault("graphql.max_depth", 10)
	viper.SetDefault("graphql.rate_limit_per_minute", 100)
	viper.SetDefault("graphql.websocket_enabled", true)
}

// GetDatabaseConnectionString returns the database connection string
func (c *Config) GetDatabaseConnectionString() string {
	return fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=%s TimeZone=%s",
		c.Database.Host,
		c.Database.Port,
		c.Database.User,
		c.Database.Password,
		c.Database.DBName,
		c.Database.SSLMode,
		c.Database.TimeZone,
	)
}

// GetRedisConnectionString returns the Redis connection string
func (c *Config) GetRedisConnectionString() string {
	return fmt.Sprintf("%s:%d", c.Redis.Host, c.Redis.Port)
}

// IsDevelopment returns true if running in development mode
func (c *Config) IsDevelopment() bool {
	return c.App.Environment == "development"
}

// IsProduction returns true if running in production mode
func (c *Config) IsProduction() bool {
	return c.App.Environment == "production"
}

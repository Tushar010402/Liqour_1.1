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
	Frontend  ServiceConfig `mapstructure:"frontend"`
}

// ServiceConfig holds individual service configuration
type ServiceConfig struct {
	Host string `mapstructure:"host"`
	Port int    `mapstructure:"port"`
	URL  string `mapstructure:"url"`
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

// setDefaults sets default configuration values
func setDefaults() {
	// Server defaults
	viper.SetDefault("server.host", "localhost")
	viper.SetDefault("server.port", 8090)
	viper.SetDefault("server.mode", "debug")
	viper.SetDefault("server.read_timeout", 10)
	viper.SetDefault("server.write_timeout", 10)
	viper.SetDefault("server.idle_timeout", 120)

	// Database defaults
	viper.SetDefault("database.host", "localhost")
	viper.SetDefault("database.port", 5432)
	viper.SetDefault("database.user", "postgres")
	viper.SetDefault("database.password", "password")
	viper.SetDefault("database.dbname", "liquorpro")
	viper.SetDefault("database.sslmode", "disable")
	viper.SetDefault("database.timezone", "UTC")

	// Redis defaults
	viper.SetDefault("redis.host", "localhost")
	viper.SetDefault("redis.port", 6379)
	viper.SetDefault("redis.password", "")
	viper.SetDefault("redis.db", 0)

	// JWT defaults
	viper.SetDefault("jwt.secret", "your-secret-key")
	viper.SetDefault("jwt.expiration_hours", 24)
	viper.SetDefault("jwt.refresh_hours", 168) // 7 days
	viper.SetDefault("jwt.issuer", "liquorpro")

	// App defaults
	viper.SetDefault("app.name", "LiquorPro")
	viper.SetDefault("app.version", "1.0.0")
	viper.SetDefault("app.environment", "development")
	viper.SetDefault("app.debug", true)
	viper.SetDefault("app.log_level", "info")

	// Services defaults
	viper.SetDefault("services.gateway.host", "localhost")
	viper.SetDefault("services.gateway.port", 8090)
	viper.SetDefault("services.auth.host", "localhost")
	viper.SetDefault("services.auth.port", 8091)
	viper.SetDefault("services.sales.host", "localhost")
	viper.SetDefault("services.sales.port", 8092)
	viper.SetDefault("services.inventory.host", "localhost")
	viper.SetDefault("services.inventory.port", 8093)
	viper.SetDefault("services.finance.host", "localhost")
	viper.SetDefault("services.finance.port", 8094)
	viper.SetDefault("services.frontend.host", "localhost")
	viper.SetDefault("services.frontend.port", 8095)
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
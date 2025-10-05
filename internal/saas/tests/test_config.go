package tests

import (
	"os"
	"strconv"

	"github.com/liquorpro/go-backend/pkg/shared/database"
)

// GetTestDatabaseConfig returns database configuration for tests
// It reads from environment variables or uses defaults matching the docker-compose setup
func GetTestDatabaseConfig() database.Config {
	host := getEnv("DATABASE_HOST", "localhost")
	portStr := getEnv("DATABASE_PORT", "5432")
	port, _ := strconv.Atoi(portStr)
	user := getEnv("DATABASE_USER", "liquorpro")
	password := getEnv("DATABASE_PASSWORD", "liquorpro_password")
	dbName := getEnv("DATABASE_NAME", "liquorpro")
	sslMode := getEnv("DATABASE_SSLMODE", "disable")
	timeZone := getEnv("DATABASE_TIMEZONE", "UTC")

	return database.Config{
		Host:     host,
		Port:     port,
		User:     user,
		Password: password,
		DBName:   dbName,
		SSLMode:  sslMode,
		TimeZone: timeZone,
	}
}

// getEnv reads an environment variable or returns a default value
func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}

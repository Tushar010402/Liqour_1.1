package main

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/liquorpro/go-backend/pkg/shared/config"
)

// Color codes for output
const (
	ColorReset  = "\033[0m"
	ColorRed    = "\033[31m"
	ColorGreen  = "\033[32m"
	ColorYellow = "\033[33m"
	ColorBlue   = "\033[34m"
	ColorPurple = "\033[35m"
	ColorCyan   = "\033[36m"
	ColorWhite  = "\033[37m"
)

type TestResult struct {
	Name        string
	Success     bool
	Message     string
	Duration    time.Duration
	StatusCode  int
	Response    string
}

func main() {
	fmt.Println(ColorBlue + "🍾 LiquorPro System Test Suite" + ColorReset)
	fmt.Println(strings.Repeat("=", 50))
	
	var results []TestResult
	
	// Test 1: Configuration Loading
	results = append(results, testConfigLoading())
	
	// Test 2: Port Configuration Verification
	results = append(results, testPortConfiguration())
	
	// Test 3: JWT Configuration
	results = append(results, testJWTConfiguration())
	
	// Test 4: Service URL Configuration
	results = append(results, testServiceURLConfiguration())
	
	// Test 5: Build Verification
	results = append(results, testBuildVerification())
	
	// Test 6: Docker Configuration
	results = append(results, testDockerConfiguration())
	
	// Print Results
	printTestResults(results)
}

func testConfigLoading() TestResult {
	start := time.Now()
	
	// Test loading configuration
	cfg, err := config.LoadConfig("config")
	if err != nil {
		return TestResult{
			Name:     "Configuration Loading",
			Success:  false,
			Message:  fmt.Sprintf("Failed to load config: %v", err),
			Duration: time.Since(start),
		}
	}
	
	// Verify critical config values
	if cfg.App.Name != "LiquorPro" {
		return TestResult{
			Name:     "Configuration Loading",
			Success:  false,
			Message:  "App name configuration incorrect",
			Duration: time.Since(start),
		}
	}
	
	return TestResult{
		Name:     "Configuration Loading",
		Success:  true,
		Message:  "Configuration loaded successfully",
		Duration: time.Since(start),
	}
}

func testPortConfiguration() TestResult {
	start := time.Now()
	
	cfg, err := config.LoadConfig("config")
	if err != nil {
		return TestResult{
			Name:     "Port Configuration",
			Success:  false,
			Message:  fmt.Sprintf("Failed to load config: %v", err),
			Duration: time.Since(start),
		}
	}
	
	expectedPorts := map[string]int{
		"gateway":   8090,
		"auth":      8091,
		"sales":     8092,
		"inventory": 8093,
		"finance":   8094,
		"frontend":  8095,
	}
	
	actualPorts := map[string]int{
		"gateway":   cfg.Services.Gateway.Port,
		"auth":      cfg.Services.Auth.Port,
		"sales":     cfg.Services.Sales.Port,
		"inventory": cfg.Services.Inventory.Port,
		"finance":   cfg.Services.Finance.Port,
		"frontend":  cfg.Services.Frontend.Port,
	}
	
	for service, expectedPort := range expectedPorts {
		if actualPorts[service] != expectedPort {
			return TestResult{
				Name:     "Port Configuration",
				Success:  false,
				Message:  fmt.Sprintf("%s port is %d, expected %d", service, actualPorts[service], expectedPort),
				Duration: time.Since(start),
			}
		}
	}
	
	return TestResult{
		Name:     "Port Configuration",
		Success:  true,
		Message:  "All ports correctly configured (8090-8095)",
		Duration: time.Since(start),
	}
}

func testJWTConfiguration() TestResult {
	start := time.Now()
	
	cfg, err := config.LoadConfig("config")
	if err != nil {
		return TestResult{
			Name:     "JWT Configuration",
			Success:  false,
			Message:  fmt.Sprintf("Failed to load config: %v", err),
			Duration: time.Since(start),
		}
	}
	
	if cfg.JWT.Secret == "" {
		return TestResult{
			Name:     "JWT Configuration",
			Success:  false,
			Message:  "JWT secret is empty",
			Duration: time.Since(start),
		}
	}
	
	if cfg.JWT.ExpirationHours == 0 {
		return TestResult{
			Name:     "JWT Configuration",
			Success:  false,
			Message:  "JWT expiration hours not configured",
			Duration: time.Since(start),
		}
	}
	
	return TestResult{
		Name:     "JWT Configuration",
		Success:  true,
		Message:  "JWT configuration is valid",
		Duration: time.Since(start),
	}
}

func testServiceURLConfiguration() TestResult {
	start := time.Now()
	
	cfg, err := config.LoadConfig("config")
	if err != nil {
		return TestResult{
			Name:     "Service URL Configuration",
			Success:  false,
			Message:  fmt.Sprintf("Failed to load config: %v", err),
			Duration: time.Since(start),
		}
	}
	
	expectedURLs := map[string]string{
		"gateway":   "http://localhost:8090",
		"auth":      "http://localhost:8091",
		"sales":     "http://localhost:8092",
		"inventory": "http://localhost:8093",
		"finance":   "http://localhost:8094",
		"frontend":  "http://localhost:8095",
	}
	
	actualURLs := map[string]string{
		"gateway":   cfg.Services.Gateway.URL,
		"auth":      cfg.Services.Auth.URL,
		"sales":     cfg.Services.Sales.URL,
		"inventory": cfg.Services.Inventory.URL,
		"finance":   cfg.Services.Finance.URL,
		"frontend":  cfg.Services.Frontend.URL,
	}
	
	for service, expectedURL := range expectedURLs {
		if actualURLs[service] != expectedURL {
			return TestResult{
				Name:     "Service URL Configuration",
				Success:  false,
				Message:  fmt.Sprintf("%s URL is %s, expected %s", service, actualURLs[service], expectedURL),
				Duration: time.Since(start),
			}
		}
	}
	
	return TestResult{
		Name:     "Service URL Configuration",
		Success:  true,
		Message:  "All service URLs correctly configured",
		Duration: time.Since(start),
	}
}

func testBuildVerification() TestResult {
	start := time.Now()
	
	services := []string{"gateway", "auth", "sales", "frontend"}
	
	for _, service := range services {
		buildPath := fmt.Sprintf("./build/test-%s", service)
		if _, err := os.Stat(buildPath); os.IsNotExist(err) {
			return TestResult{
				Name:     "Build Verification",
				Success:  false,
				Message:  fmt.Sprintf("Binary for %s service not found: %s", service, buildPath),
				Duration: time.Since(start),
			}
		}
	}
	
	return TestResult{
		Name:     "Build Verification",
		Success:  true,
		Message:  "All service binaries built successfully",
		Duration: time.Since(start),
	}
}

func testDockerConfiguration() TestResult {
	start := time.Now()
	
	// Check if docker-compose files exist and are valid
	files := []string{
		"docker-compose.yml",
		"docker-compose.dev.yml",
	}
	
	for _, file := range files {
		if _, err := os.Stat(file); os.IsNotExist(err) {
			return TestResult{
				Name:     "Docker Configuration",
				Success:  false,
				Message:  fmt.Sprintf("Docker compose file not found: %s", file),
				Duration: time.Since(start),
			}
		}
		
		// Read and check if it contains the new ports
		content, err := os.ReadFile(file)
		if err != nil {
			return TestResult{
				Name:     "Docker Configuration",
				Success:  false,
				Message:  fmt.Sprintf("Failed to read %s: %v", file, err),
				Duration: time.Since(start),
			}
		}
		
		contentStr := string(content)
		newPorts := []string{"8090", "8091", "8092", "8093", "8094", "8095"}
		oldPorts := []string{"8080", "8081", "8082", "8083", "8084", "8085"}
		
		for _, oldPort := range oldPorts {
			if strings.Contains(contentStr, oldPort) {
				return TestResult{
					Name:     "Docker Configuration",
					Success:  false,
					Message:  fmt.Sprintf("Found old port %s in %s", oldPort, file),
					Duration: time.Since(start),
				}
			}
		}
		
		hasNewPorts := false
		for _, newPort := range newPorts {
			if strings.Contains(contentStr, newPort) {
				hasNewPorts = true
				break
			}
		}
		
		if !hasNewPorts {
			return TestResult{
				Name:     "Docker Configuration",
				Success:  false,
				Message:  fmt.Sprintf("New ports (8090-8095) not found in %s", file),
				Duration: time.Since(start),
			}
		}
	}
	
	return TestResult{
		Name:     "Docker Configuration",
		Success:  true,
		Message:  "Docker configuration updated correctly",
		Duration: time.Since(start),
	}
}

func printTestResults(results []TestResult) {
	fmt.Println()
	fmt.Println(ColorBlue + "📋 Test Results" + ColorReset)
	fmt.Println(strings.Repeat("-", 80))
	
	successCount := 0
	totalDuration := time.Duration(0)
	
	for i, result := range results {
		status := ColorRed + "FAIL" + ColorReset
		if result.Success {
			status = ColorGreen + "PASS" + ColorReset
			successCount++
		}
		
		fmt.Printf("%d. %-30s [%s] %s (%.2fms)\n", 
			i+1, result.Name, status, result.Message, float64(result.Duration.Nanoseconds())/1e6)
		
		if result.StatusCode > 0 {
			fmt.Printf("   Status Code: %d\n", result.StatusCode)
		}
		
		if result.Response != "" && len(result.Response) < 200 {
			fmt.Printf("   Response: %s\n", result.Response)
		}
		
		totalDuration += result.Duration
	}
	
	fmt.Println(strings.Repeat("-", 80))
	
	successRate := float64(successCount) / float64(len(results)) * 100
	
	color := ColorRed
	if successRate == 100 {
		color = ColorGreen
	} else if successRate >= 80 {
		color = ColorYellow
	}
	
	fmt.Printf("📊 Summary: %s%d/%d tests passed (%.1f%%)%s\n", 
		color, successCount, len(results), successRate, ColorReset)
	fmt.Printf("⏱️  Total Duration: %.2fms\n", float64(totalDuration.Nanoseconds())/1e6)
	
	if successRate == 100 {
		fmt.Println()
		fmt.Println(ColorGreen + "🎉 All tests passed! System is ready for deployment." + ColorReset)
		fmt.Println()
		fmt.Println("🚀 " + ColorBlue + "To start the development environment:" + ColorReset)
		fmt.Println("   make dev")
		fmt.Println("   # or")  
		fmt.Println("   docker-compose -f docker-compose.dev.yml up")
		fmt.Println()
		fmt.Println("🌐 " + ColorBlue + "Access URLs:" + ColorReset)
		fmt.Println("   Frontend:     http://localhost:8095")
		fmt.Println("   API Gateway:  http://localhost:8090")
		fmt.Println("   Auth:         http://localhost:8091") 
		fmt.Println("   Sales:        http://localhost:8092")
		fmt.Println("   Inventory:    http://localhost:8093")
		fmt.Println("   Finance:      http://localhost:8094")
	} else {
		fmt.Println()
		fmt.Println(ColorRed + "❌ Some tests failed. Please review the issues above." + ColorReset)
	}
}
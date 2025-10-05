# LiquorPro Makefile
# Modern liquor shop management system

.PHONY: help build test clean run dev prod docker k8s

# Default target
all: build

# Display help information
help:
	@echo "🍾 LiquorPro - Build Commands"
	@echo "============================="
	@echo ""
	@echo "Development Commands:"
	@echo "  dev         Start development environment with Docker Compose"
	@echo "  dev-logs    View development environment logs"
	@echo "  dev-stop    Stop development environment"
	@echo ""
	@echo "Build Commands:"
	@echo "  build       Build all Go services"
	@echo "  clean       Clean build artifacts"
	@echo "  test        Run all tests"
	@echo "  lint        Run linters and code quality checks"
	@echo ""
	@echo "Local Development:"
	@echo "  run         Run all services locally (requires local DB/Redis)"
	@echo "  run-gateway Run only the API gateway"
	@echo "  run-auth    Run only the auth service"
	@echo "  run-sales   Run only the sales service"
	@echo ""
	@echo "Docker Commands:"
	@echo "  docker      Build all Docker images"
	@echo "  docker-up   Start production environment with Docker Compose"
	@echo "  docker-down Stop production environment"
	@echo ""
	@echo "Kubernetes Commands:"
	@echo "  k8s-deploy  Deploy to Kubernetes cluster"
	@echo "  k8s-status  Check Kubernetes deployment status"
	@echo "  k8s-clean   Remove Kubernetes deployment"
	@echo ""
	@echo "Database Commands:"
	@echo "  db-create   Create database and run migrations"
	@echo "  db-migrate  Run database migrations"
	@echo "  db-seed     Seed database with sample data"
	@echo ""

# Development Environment
dev:
	@echo "🚀 Starting development environment..."
	./scripts/start-dev.sh

dev-logs:
	@echo "📋 Showing development logs..."
	docker-compose -f docker-compose.dev.yml logs -f

dev-stop:
	@echo "🛑 Stopping development environment..."
	docker-compose -f docker-compose.dev.yml down

dev-rebuild:
	@echo "🔄 Rebuilding development environment..."
	docker-compose -f docker-compose.dev.yml down
	docker-compose -f docker-compose.dev.yml build --no-cache
	docker-compose -f docker-compose.dev.yml up -d

# Build Commands
build:
	@echo "🔨 Building all services..."
	./scripts/build-all.sh

clean:
	@echo "🧹 Cleaning build artifacts..."
	rm -rf build/
	rm -rf vendor/
	go clean -cache
	go clean -modcache
	docker system prune -f

# Testing
test:
	@echo "🧪 Running tests..."
	go test -v ./...

test-coverage:
	@echo "📊 Running tests with coverage..."
	go test -v -cover ./...
	go test -v -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

test-integration:
	@echo "🔗 Running integration tests..."
	docker-compose -f docker-compose.test.yml up --build --abort-on-container-exit
	docker-compose -f docker-compose.test.yml down

# Code Quality
lint:
	@echo "🔍 Running linters..."
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run ./...; \
	else \
		echo "golangci-lint not found, running basic go vet..."; \
		go vet ./...; \
		go fmt ./...; \
	fi

format:
	@echo "✨ Formatting code..."
	go fmt ./...
	goimports -w .

# Local Development (requires local PostgreSQL and Redis)
run: build
	@echo "🏃 Running all services locally..."
	./build/gateway &
	./build/auth &
	./build/sales &
	./build/inventory &
	./build/finance &
	@echo "All services started. Use 'make stop' to stop them."

run-gateway: build
	@echo "🚪 Running API Gateway..."
	./build/gateway

run-auth: build
	@echo "🔐 Running Auth Service..."
	./build/auth

run-sales: build
	@echo "💰 Running Sales Service..."
	./build/sales

run-inventory: build
	@echo "📦 Running Inventory Service..."
	./build/inventory

run-finance: build
	@echo "💳 Running Finance Service..."
	./build/finance


stop:
	@echo "🛑 Stopping local services..."
	pkill -f "./build/gateway" || true
	pkill -f "./build/auth" || true
	pkill -f "./build/sales" || true
	pkill -f "./build/inventory" || true
	pkill -f "./build/finance" || true

# Docker Commands
docker:
	@echo "🐳 Building Docker images..."
	docker-compose build

docker-up:
	@echo "🐳 Starting production environment..."
	docker-compose up -d
	@echo "Production environment started!"
	@echo "Frontend: http://localhost:8095"
	@echo "API: http://localhost:8090"

docker-down:
	@echo "🐳 Stopping production environment..."
	docker-compose down

docker-logs:
	@echo "📋 Showing production logs..."
	docker-compose logs -f

docker-rebuild:
	@echo "🔄 Rebuilding production environment..."
	docker-compose down
	docker-compose build --no-cache
	docker-compose up -d

# Kubernetes Commands
k8s-deploy:
	@echo "☸️  Deploying to Kubernetes..."
	./scripts/deploy-k8s.sh

k8s-status:
	@echo "☸️  Checking Kubernetes status..."
	kubectl get pods -n liquorpro
	kubectl get services -n liquorpro
	kubectl get ingress -n liquorpro

k8s-clean:
	@echo "☸️  Cleaning Kubernetes deployment..."
	kubectl delete namespace liquorpro --ignore-not-found=true

k8s-logs:
	@echo "📋 Showing Kubernetes logs..."
	kubectl logs -f deployment/gateway -n liquorpro

# Database Commands
db-create:
	@echo "🗄️  Creating database..."
	docker-compose -f docker-compose.dev.yml up -d postgres
	sleep 5
	docker-compose -f docker-compose.dev.yml exec postgres createdb -U dev_user liquorpro_dev || true

db-migrate:
	@echo "🗄️  Running database migrations..."
	# Add migration commands here when implemented

db-seed:
	@echo "🌱 Seeding database with sample data..."
	# Add seed commands here when implemented

db-reset:
	@echo "🗄️  Resetting database..."
	docker-compose -f docker-compose.dev.yml down
	docker volume rm $$(docker volume ls -q | grep postgres) || true
	docker-compose -f docker-compose.dev.yml up -d postgres

# Utility Commands
deps:
	@echo "📦 Installing dependencies..."
	go mod download
	go mod tidy

update-deps:
	@echo "⬆️  Updating dependencies..."
	go get -u ./...
	go mod tidy

# Security
security-check:
	@echo "🔒 Running security checks..."
	@if command -v gosec >/dev/null 2>&1; then \
		gosec ./...; \
	else \
		echo "gosec not found. Install with: go install github.com/securecodewarrior/gosec/v2/cmd/gosec@latest"; \
	fi

# Monitoring
monitor:
	@echo "📊 Starting monitoring stack..."
	docker-compose --profile monitoring up -d
	@echo "Prometheus: http://localhost:9090"
	@echo "Grafana: http://localhost:3000 (admin/admin123)"

monitor-stop:
	@echo "📊 Stopping monitoring stack..."
	docker-compose --profile monitoring down

# Install development tools
install-tools:
	@echo "🛠️  Installing development tools..."
	go install golang.org/x/tools/cmd/goimports@latest
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	go install github.com/securecodewarrior/gosec/v2/cmd/gosec@latest

# Performance testing
perf-test:
	@echo "⚡ Running performance tests..."
	@if command -v wrk >/dev/null 2>&1; then \
		wrk -t12 -c400 -d30s http://localhost:8090/health; \
	else \
		echo "wrk not found. Install wrk for performance testing."; \
	fi

# Documentation
docs:
	@echo "📚 Generating documentation..."
	@if command -v godoc >/dev/null 2>&1; then \
		godoc -http=:6060; \
		echo "Documentation server started at http://localhost:6060"; \
	else \
		echo "godoc not found. Install with: go install golang.org/x/tools/cmd/godoc@latest"; \
	fi

# Release
release:
	@echo "🚀 Building release..."
	@if [ -z "$(VERSION)" ]; then \
		echo "Usage: make release VERSION=v1.0.0"; \
		exit 1; \
	fi
	git tag $(VERSION)
	git push origin $(VERSION)
	make build
	tar -czf liquorpro-$(VERSION)-linux-amd64.tar.gz build/
	@echo "Release $(VERSION) created: liquorpro-$(VERSION)-linux-amd64.tar.gz"

# Quick start for new developers
quick-start:
	@echo "🍾 LiquorPro Quick Start"
	@echo "======================="
	@echo "1. Installing dependencies..."
	make deps
	@echo "2. Starting development environment..."
	make dev
	@echo ""
	@echo "✅ Quick start completed!"
	@echo "📱 Access the application at: http://localhost:8095"
	@echo "🔧 View logs with: make dev-logs"
	@echo "❓ Get help with: make help"
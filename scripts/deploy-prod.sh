#!/bin/bash

# LiquorPro Production Deployment Script
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION=${1:-latest}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Check if docker-compose is available
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose is not installed. Please install docker-compose and try again."
        exit 1
    fi
    
    # Check if .env file exists
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        log_warning ".env file not found. Please create one based on env.example"
        if [[ -f "$PROJECT_ROOT/env.example" ]]; then
            log_info "Copying env.example to .env..."
            cp "$PROJECT_ROOT/env.example" "$PROJECT_ROOT/.env"
            log_warning "Please edit .env file with your production values before continuing."
            exit 1
        fi
    fi
    
    log_success "Prerequisites check passed"
}

# Build production images
build_images() {
    log_info "Building production images..."
    
    cd "$PROJECT_ROOT"
    
    # Build all service images
    log_info "Building Gateway service..."
    docker build -f Dockerfile.gateway -t liquorpro/gateway:$VERSION .
    
    log_info "Building Auth service..."
    docker build -f Dockerfile.auth -t liquorpro/auth:$VERSION .
    
    log_info "Building Sales service..."
    docker build -f Dockerfile.sales -t liquorpro/sales:$VERSION .
    
    log_info "Building Inventory service..."
    docker build -f Dockerfile.inventory -t liquorpro/inventory:$VERSION .
    
    log_info "Building Finance service..."
    docker build -f Dockerfile.finance -t liquorpro/finance:$VERSION .
    
    # Tag as latest if version is not latest
    if [[ "$VERSION" != "latest" ]]; then
        docker tag liquorpro/gateway:$VERSION liquorpro/gateway:latest
        docker tag liquorpro/auth:$VERSION liquorpro/auth:latest
        docker tag liquorpro/sales:$VERSION liquorpro/sales:latest
        docker tag liquorpro/inventory:$VERSION liquorpro/inventory:latest
        docker tag liquorpro/finance:$VERSION liquorpro/finance:latest
    fi
    
    log_success "All images built successfully"
}

# Setup production directories
setup_directories() {
    log_info "Setting up production directories..."
    
    # Create necessary directories
    mkdir -p "$PROJECT_ROOT/backups"
    mkdir -p "$PROJECT_ROOT/logs"
    mkdir -p "$PROJECT_ROOT/nginx/logs"
    mkdir -p "$PROJECT_ROOT/nginx/ssl"
    
    # Set proper permissions
    chmod 755 "$PROJECT_ROOT/backups"
    chmod 755 "$PROJECT_ROOT/logs"
    
    log_success "Production directories created"
}

# Setup nginx configuration
setup_nginx() {
    log_info "Setting up Nginx configuration..."
    
    if [[ ! -f "$PROJECT_ROOT/nginx/nginx.prod.conf" ]]; then
        cat > "$PROJECT_ROOT/nginx/nginx.prod.conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream gateway {
        server gateway:8090;
    }
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    
    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    server {
        listen 80;
        server_name _;
        
        # Health check endpoint
        location /health {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
        
        # Redirect HTTP to HTTPS in production
        location / {
            return 301 https://$server_name$request_uri;
        }
    }
    
    server {
        listen 443 ssl http2;
        server_name api.yourdomain.com;
        
        # SSL configuration (update paths for your certificates)
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
        
        # Rate limiting
        limit_req zone=api burst=20 nodelay;
        
        # Proxy to Gateway service
        location / {
            proxy_pass http://gateway;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
    }
}
EOF
        log_success "Nginx configuration created"
    else
        log_info "Nginx configuration already exists"
    fi
}

# Deploy production stack
deploy_stack() {
    log_info "Deploying production stack..."
    
    cd "$PROJECT_ROOT"
    
    # Export version for docker-compose
    export VERSION=$VERSION
    
    # Stop any existing containers
    log_info "Stopping existing containers..."
    docker-compose -f docker-compose.prod.yml down || true
    
    # Start production stack
    log_info "Starting production services..."
    docker-compose -f docker-compose.prod.yml up -d
    
    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    sleep 30
    
    # Check service health
    check_service_health
    
    log_success "Production stack deployed successfully"
}

# Check service health
check_service_health() {
    log_info "Checking service health..."
    
    local services=("postgres" "redis" "gateway" "auth" "sales" "inventory" "finance")
    local all_healthy=true
    
    for service in "${services[@]}"; do
        if docker-compose -f docker-compose.prod.yml ps --services --filter "status=running" | grep -q "$service"; then
            log_success "$service is running"
        else
            log_error "$service is not running"
            all_healthy=false
        fi
    done
    
    if [[ "$all_healthy" == true ]]; then
        log_success "All services are healthy"
    else
        log_error "Some services are not healthy. Check logs for details."
        return 1
    fi
}

# Setup database backups
setup_backups() {
    log_info "Setting up database backups..."
    
    # Create backup script
    cat > "$PROJECT_ROOT/scripts/backup-db.sh" << 'EOF'
#!/bin/bash
set -e

BACKUP_DIR="/app/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="liquorpro_backup_${DATE}.sql"

echo "Starting database backup..."
docker exec liquorpro-prod-postgres pg_dump -U $DB_USER -d liquorpro > "${BACKUP_DIR}/${BACKUP_FILE}"

echo "Compressing backup..."
gzip "${BACKUP_DIR}/${BACKUP_FILE}"

echo "Cleaning old backups (keeping last 30 days)..."
find "${BACKUP_DIR}" -name "*.sql.gz" -mtime +30 -delete

echo "Backup completed: ${BACKUP_FILE}.gz"
EOF
    
    chmod +x "$PROJECT_ROOT/scripts/backup-db.sh"
    
    # Setup cron job for automated backups (optional)
    log_info "Backup script created at scripts/backup-db.sh"
    log_info "To setup automated backups, add this to your crontab:"
    echo "0 2 * * * $PROJECT_ROOT/scripts/backup-db.sh >> $PROJECT_ROOT/logs/backup.log 2>&1"
    
    log_success "Database backup setup completed"
}

# Show deployment information
show_deployment_info() {
    echo ""
    log_success "🎉 LiquorPro Production Deployment Completed!"
    echo ""
    echo "Service URLs:"
    echo "============="
    echo "🚪 API Gateway:    https://api.yourdomain.com"
    echo "🔐 Auth Service:   http://localhost:8091"
    echo "💰 Sales Service:  http://localhost:8092"
    echo "📦 Inventory:      http://localhost:8093"
    echo "💳 Finance:        http://localhost:8094"
    echo ""
    echo "Management:"
    echo "==========="
    echo "📊 Logs:           $PROJECT_ROOT/logs/"
    echo "💾 Backups:        $PROJECT_ROOT/backups/"
    echo "🔧 Config:         $PROJECT_ROOT/.env"
    echo ""
    echo "Useful Commands:"
    echo "==============="
    echo "# View all service logs"
    echo "docker-compose -f docker-compose.prod.yml logs -f"
    echo ""
    echo "# View specific service logs"
    echo "docker-compose -f docker-compose.prod.yml logs -f gateway"
    echo ""
    echo "# Check service status"
    echo "docker-compose -f docker-compose.prod.yml ps"
    echo ""
    echo "# Restart all services"
    echo "docker-compose -f docker-compose.prod.yml restart"
    echo ""
    echo "# Stop all services"
    echo "docker-compose -f docker-compose.prod.yml down"
    echo ""
    echo "# Run database backup"
    echo "./scripts/backup-db.sh"
    echo ""
}

# Main deployment flow
main() {
    echo "🚀 LiquorPro Production Deployment"
    echo "=================================="
    echo "Version: $VERSION"
    echo ""
    
    check_prerequisites
    setup_directories
    setup_nginx
    build_images
    deploy_stack
    setup_backups
    show_deployment_info
}

# Run main function
main "$@"
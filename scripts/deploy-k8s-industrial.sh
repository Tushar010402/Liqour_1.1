#!/bin/bash

# LiquorPro Kubernetes Deployment Script
# Industrial-grade deployment with Kafka and Istio service mesh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="liquorpro"
KAFKA_NAMESPACE="liquorpro-kafka"
MONITORING_NAMESPACE="liquorpro-monitoring"
DOCKER_REGISTRY="liquorpro"
VERSION="latest"

# Functions
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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi

    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed. Please install helm first."
        exit 1
    fi

    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi

    # Check if Istio is installed
    if ! kubectl get namespace istio-system &> /dev/null; then
        log_warning "Istio is not installed. Installing Istio..."
        install_istio
    fi

    log_success "Prerequisites check completed"
}

install_istio() {
    log_step "Installing Istio service mesh..."

    # Download and install istioctl
    curl -L https://istio.io/downloadIstio | sh -
    export PATH="$PWD/istio-*/bin:$PATH"

    # Install Istio
    istioctl install --set values.defaultRevision=default -y

    # Enable Istio injection for namespaces
    kubectl label namespace default istio-injection=enabled --overwrite

    log_success "Istio installed successfully"
}

build_docker_images() {
    log_step "Building Docker images..."

    # Build all service images
    services=("gateway" "auth" "sales" "inventory" "finance" "saas")

    for service in "${services[@]}"; do
        log_info "Building $service image..."
        docker build -f "Dockerfile.$service" -t "$DOCKER_REGISTRY/$service:$VERSION" .

        # Push to registry (uncomment if using external registry)
        # docker push "$DOCKER_REGISTRY/$service:$VERSION"
    done

    log_success "Docker images built successfully"
}

create_namespaces() {
    log_step "Creating Kubernetes namespaces..."

    kubectl apply -f k8s/infrastructure/namespace.yaml

    # Wait for namespaces to be ready
    kubectl wait --for=condition=Active namespace/$NAMESPACE --timeout=60s
    kubectl wait --for=condition=Active namespace/$KAFKA_NAMESPACE --timeout=60s
    kubectl wait --for=condition=Active namespace/$MONITORING_NAMESPACE --timeout=60s

    log_success "Namespaces created successfully"
}

deploy_infrastructure() {
    log_step "Deploying infrastructure components..."

    # Deploy PostgreSQL
    log_info "Deploying PostgreSQL..."
    kubectl apply -f k8s/infrastructure/postgres.yaml
    kubectl wait --for=condition=Available deployment/postgres -n $NAMESPACE --timeout=300s

    # Deploy Redis
    log_info "Deploying Redis..."
    kubectl apply -f k8s/infrastructure/redis.yaml
    kubectl wait --for=condition=Available deployment/redis -n $NAMESPACE --timeout=300s

    # Deploy Kafka
    log_info "Deploying Kafka cluster..."
    kubectl apply -f k8s/infrastructure/kafka.yaml
    kubectl wait --for=condition=Available deployment/kafka -n $KAFKA_NAMESPACE --timeout=600s

    log_success "Infrastructure components deployed successfully"
}

deploy_rbac() {
    log_step "Deploying RBAC configuration..."

    kubectl apply -f k8s/applications/rbac.yaml

    log_success "RBAC configuration deployed successfully"
}

deploy_applications() {
    log_step "Deploying application services..."

    # Deploy services in order
    services=("auth" "inventory" "finance" "sales" "saas" "gateway")

    for service in "${services[@]}"; do
        log_info "Deploying $service service..."
        kubectl apply -f "k8s/applications/$service.yaml"
        kubectl wait --for=condition=Available "deployment/$service" -n $NAMESPACE --timeout=300s
    done

    log_success "Application services deployed successfully"
}

configure_istio() {
    log_step "Configuring Istio service mesh..."

    # Apply Istio configurations
    kubectl apply -f k8s/istio/gateway.yaml
    kubectl apply -f k8s/istio/security.yaml
    kubectl apply -f k8s/istio/telemetry.yaml

    log_success "Istio service mesh configured successfully"
}

deploy_monitoring() {
    log_step "Deploying monitoring stack..."

    # Deploy Prometheus
    log_info "Deploying Prometheus..."
    kubectl apply -f k8s/monitoring/prometheus.yaml
    kubectl wait --for=condition=Available deployment/prometheus -n $MONITORING_NAMESPACE --timeout=300s

    # Deploy Grafana
    log_info "Deploying Grafana..."
    kubectl apply -f k8s/monitoring/grafana.yaml
    kubectl wait --for=condition=Available deployment/grafana -n $MONITORING_NAMESPACE --timeout=300s

    # Deploy Jaeger
    log_info "Deploying Jaeger..."
    kubectl apply -f k8s/monitoring/jaeger.yaml
    kubectl wait --for=condition=Available deployment/jaeger-collector -n $MONITORING_NAMESPACE --timeout=300s
    kubectl wait --for=condition=Available deployment/jaeger-query -n $MONITORING_NAMESPACE --timeout=300s

    log_success "Monitoring stack deployed successfully"
}

configure_ingress() {
    log_step "Configuring ingress and load balancing..."

    # Install NGINX Ingress Controller if not present
    if ! kubectl get deployment ingress-nginx-controller -n ingress-nginx &> /dev/null; then
        log_info "Installing NGINX Ingress Controller..."
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
        kubectl wait --for=condition=Available deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s
    fi

    # Apply ingress configurations
    kubectl apply -f k8s/infrastructure/ingress.yaml

    log_success "Ingress and load balancing configured successfully"
}

run_database_migrations() {
    log_step "Running database migrations..."

    # Wait for PostgreSQL to be ready
    kubectl wait --for=condition=Ready pod -l app=postgres -n $NAMESPACE --timeout=300s

    # Run migrations using a job
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  namespace: $NAMESPACE
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: migration
        image: $DOCKER_REGISTRY/gateway:$VERSION
        command: ["/app/migrate"]
        env:
        - name: DATABASE_HOST
          value: "postgres"
        - name: DATABASE_PORT
          value: "5432"
        - name: DATABASE_USER
          value: "liquorpro"
        - name: DATABASE_PASSWORD
          value: "liquorpro_password"
        - name: DATABASE_NAME
          value: "liquorpro"
      serviceAccountName: liquorpro-sa
EOF

    kubectl wait --for=condition=Complete job/db-migration -n $NAMESPACE --timeout=600s

    log_success "Database migrations completed successfully"
}

verify_deployment() {
    log_step "Verifying deployment..."

    # Check pod status
    log_info "Checking pod status..."
    kubectl get pods -n $NAMESPACE
    kubectl get pods -n $KAFKA_NAMESPACE
    kubectl get pods -n $MONITORING_NAMESPACE

    # Check service status
    log_info "Checking service status..."
    kubectl get services -n $NAMESPACE

    # Check ingress status
    log_info "Checking ingress status..."
    kubectl get ingress -n $NAMESPACE

    # Perform health checks
    log_info "Performing health checks..."

    # Wait for all deployments to be ready
    kubectl wait --for=condition=Available deployment --all -n $NAMESPACE --timeout=600s

    # Check if services are responding
    local gateway_pod=$(kubectl get pods -n $NAMESPACE -l app=gateway -o jsonpath='{.items[0].metadata.name}')
    if kubectl exec -n $NAMESPACE "$gateway_pod" -- curl -f http://localhost:8090/health > /dev/null 2>&1; then
        log_success "Gateway health check passed"
    else
        log_warning "Gateway health check failed"
    fi

    log_success "Deployment verification completed"
}

show_access_info() {
    log_step "Deployment completed successfully!"

    # Get ingress IP
    local ingress_ip=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    LiquorPro Deployment                    ║${NC}"
    echo -e "${CYAN}║                     Access Information                     ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}🚀 Application URLs:${NC}"
    echo -e "   📱 Main API:          https://api.liquorpro.com"
    echo -e "   🔧 Admin Dashboard:   https://admin.liquorpro.com"
    echo -e "   📊 Grafana:          https://grafana.liquorpro.com"
    echo -e "   🔍 Prometheus:       https://prometheus.liquorpro.com"
    echo -e "   🕵️ Jaeger:           https://jaeger.liquorpro.com"
    echo ""
    echo -e "${GREEN}🔑 Default Credentials:${NC}"
    echo -e "   📊 Grafana:          admin / LiquorPro2024!"
    echo -e "   🔍 Monitoring:       admin / liquorpro123"
    echo ""
    echo -e "${GREEN}📡 Load Balancer IP:${NC} $ingress_ip"
    echo ""
    echo -e "${GREEN}🏗️ Infrastructure:${NC}"
    echo -e "   📦 Kubernetes:       $(kubectl version --short --client 2>/dev/null | grep Client || echo 'Unknown')"
    echo -e "   🕸️ Istio:            Service Mesh Enabled"
    echo -e "   📨 Kafka:            3-node cluster"
    echo -e "   🐘 PostgreSQL:       High-availability setup"
    echo -e "   📊 Redis:            Caching layer"
    echo ""
    echo -e "${YELLOW}⚠️ Next Steps:${NC}"
    echo -e "   1. Update DNS records to point to the load balancer IP"
    echo -e "   2. Configure TLS certificates (cert-manager will auto-provision Let's Encrypt)"
    echo -e "   3. Set up monitoring alerts in Grafana"
    echo -e "   4. Configure backup strategies for PostgreSQL"
    echo -e "   5. Review and adjust resource limits based on usage"
    echo ""
    echo -e "${CYAN}🎉 Your LiquorPro backend is now running with industrial-grade infrastructure!${NC}"
    echo ""
}

# Main deployment flow
main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                      LiquorPro Kubernetes Deployment                        ║"
    echo "║                    Industrial-Grade Infrastructure                          ║"
    echo "║                                                                              ║"
    echo "║  🔧 Microservices Architecture                                              ║"
    echo "║  🕸️ Istio Service Mesh                                                      ║"
    echo "║  📨 Apache Kafka Message Broker                                             ║"
    echo "║  📊 Complete Observability Stack                                            ║"
    echo "║  🔒 Enterprise Security                                                     ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""

    # Deployment steps
    check_prerequisites
    build_docker_images
    create_namespaces
    deploy_rbac
    deploy_infrastructure
    deploy_applications
    configure_istio
    deploy_monitoring
    configure_ingress
    run_database_migrations
    verify_deployment
    show_access_info
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"
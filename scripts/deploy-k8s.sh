#!/bin/bash

# LiquorPro - Kubernetes Deployment Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl to deploy to Kubernetes."
    exit 1
fi

# Check if connected to cluster
if ! kubectl cluster-info &> /dev/null; then
    print_error "Not connected to a Kubernetes cluster. Please configure kubectl."
    exit 1
fi

print_status "🍾 LiquorPro - Kubernetes Deployment"
echo "======================================"

# Get cluster info
CLUSTER_NAME=$(kubectl config current-context)
print_status "Deploying to cluster: $CLUSTER_NAME"

# Confirm deployment
if [ "$1" != "--yes" ]; then
    echo ""
    print_warning "This will deploy LiquorPro to the current Kubernetes cluster."
    print_warning "Cluster: $CLUSTER_NAME"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled."
        exit 0
    fi
fi

# Create namespace
print_status "Creating namespace..."
kubectl apply -f k8s/namespace.yaml

# Deploy secrets and config
print_status "Deploying secrets and configuration..."
kubectl apply -f k8s/secrets.yaml

# Deploy database services
print_status "Deploying PostgreSQL..."
kubectl apply -f k8s/postgres.yaml

print_status "Deploying Redis..."
kubectl apply -f k8s/redis.yaml

# Wait for databases to be ready
print_status "Waiting for databases to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n liquorpro --timeout=300s
kubectl wait --for=condition=ready pod -l app=redis -n liquorpro --timeout=300s

# Deploy API Gateway
print_status "Deploying API Gateway..."
kubectl apply -f k8s/gateway.yaml

# Deploy microservices
print_status "Deploying microservices..."
kubectl apply -f k8s/microservices.yaml

# Wait for services to be ready
print_status "Waiting for services to be ready..."
kubectl wait --for=condition=ready pod -l app=gateway -n liquorpro --timeout=300s
kubectl wait --for=condition=ready pod -l app=auth -n liquorpro --timeout=300s
kubectl wait --for=condition=ready pod -l app=sales -n liquorpro --timeout=300s
kubectl wait --for=condition=ready pod -l app=inventory -n liquorpro --timeout=300s
kubectl wait --for=condition=ready pod -l app=finance -n liquorpro --timeout=300s
kubectl wait --for=condition=ready pod -l app=frontend -n liquorpro --timeout=300s

# Deploy ingress
if kubectl get ingressclass nginx &> /dev/null; then
    print_status "Deploying ingress..."
    kubectl apply -f k8s/ingress.yaml
    print_success "Ingress deployed successfully!"
    
    echo ""
    print_status "📋 Access URLs:"
    echo "Frontend: https://liquorpro.example.com"
    echo "API: https://api.liquorpro.example.com"
    echo ""
    print_warning "Note: Update DNS records to point to your ingress controller's external IP."
else
    print_warning "NGINX Ingress Controller not found. Ingress not deployed."
    print_status "You can still access services using port-forwarding:"
    echo "  kubectl port-forward -n liquorpro svc/frontend 8095:8095"
    echo "  kubectl port-forward -n liquorpro svc/gateway 8090:8090"
fi

# Display deployment status
echo ""
print_status "📊 Deployment Status:"
echo "===================="
kubectl get pods -n liquorpro
echo ""

print_status "🔍 Service Status:"
echo "=================="
kubectl get services -n liquorpro
echo ""

# Display useful commands
echo ""
print_status "🛠️  Useful Commands:"
echo "===================="
echo "View logs:         kubectl logs -f deployment/[service-name] -n liquorpro"
echo "Scale service:     kubectl scale deployment [service-name] --replicas=[count] -n liquorpro"
echo "Port forward:      kubectl port-forward -n liquorpro svc/[service-name] [local-port]:[service-port]"
echo "Get pods:          kubectl get pods -n liquorpro"
echo "Describe pod:      kubectl describe pod [pod-name] -n liquorpro"
echo "Enter pod:         kubectl exec -it [pod-name] -n liquorpro -- /bin/sh"
echo ""

# Check HPA status
if kubectl get hpa -n liquorpro &> /dev/null; then
    print_status "🔄 Auto-scaling Status:"
    echo "======================="
    kubectl get hpa -n liquorpro
    echo ""
fi

print_success "🍾 LiquorPro deployed successfully to Kubernetes!"

# Final health check
print_status "🏥 Performing health checks..."
GATEWAY_POD=$(kubectl get pods -n liquorpro -l app=gateway -o jsonpath='{.items[0].metadata.name}')

if [ ! -z "$GATEWAY_POD" ]; then
    if kubectl exec -n liquorpro $GATEWAY_POD -- wget -q --spider http://localhost:8090/health; then
        print_success "Gateway health check passed ✓"
    else
        print_warning "Gateway health check failed ✗"
    fi
else
    print_warning "No gateway pod found for health check"
fi

echo ""
print_success "Deployment completed! 🎉"
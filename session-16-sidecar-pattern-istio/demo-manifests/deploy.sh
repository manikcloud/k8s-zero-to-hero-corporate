#!/bin/bash

# Kubernetes Sidecar Pattern Demo - Deployment Script
# This script deploys Apache HTTPD with Istio sidecar injection

set -e

echo "🚀 Kubernetes Sidecar Pattern Demo Deployment"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if istioctl is available
if ! command -v istioctl &> /dev/null; then
    print_warning "istioctl is not installed. Installing Istio..."
    curl -L https://istio.io/downloadIstio | sh -
    cd istio-*
    export PATH=$PWD/bin:$PATH
    cd ..
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

print_header "1. Installing Istio (if not already installed)"
if ! kubectl get namespace istio-system &> /dev/null; then
    print_status "Installing Istio control plane..."
    istioctl install --set values.defaultRevision=default -y
    print_status "Istio installed successfully"
else
    print_status "Istio is already installed"
fi

print_header "2. Enabling sidecar injection for default namespace"
kubectl label namespace default istio-injection=enabled --overwrite
print_status "Sidecar injection enabled for default namespace"

print_header "3. Deploying Apache HTTPD application"
kubectl apply -f httpd-deployment.yaml
kubectl apply -f httpd-service.yaml
print_status "Application deployed successfully"

print_header "4. Configuring Istio Gateway and VirtualService"
kubectl apply -f istio-gateway.yaml
print_status "Istio networking configured"

print_header "5. Applying security policies"
kubectl apply -f istio-security.yaml
print_status "Security policies applied"

print_header "6. Waiting for deployment to be ready"
kubectl wait --for=condition=available --timeout=300s deployment/httpd-deployment
print_status "Deployment is ready"

print_header "7. Verification"
echo ""
print_status "Checking pod status (should show 2/2 containers):"
kubectl get pods -l app=httpd

echo ""
print_status "Checking services:"
kubectl get services

echo ""
print_status "Checking Istio configuration:"
kubectl get gateway,virtualservice,destinationrule

echo ""
print_header "8. Access Information"
echo ""
print_status "To access the application:"

# Get the external IP of the Istio ingress gateway
INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')

if [ -z "$INGRESS_HOST" ]; then
    INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
fi

if [ -z "$INGRESS_HOST" ]; then
    print_warning "External LoadBalancer not available. Using port-forward instead:"
    echo "kubectl port-forward -n istio-system service/istio-ingressgateway 8080:80"
    echo "Then visit: http://localhost:8080"
else
    echo "External URL: http://$INGRESS_HOST:$INGRESS_PORT"
fi

echo ""
print_header "9. Useful Commands"
echo ""
echo "# View pod details (notice 2 containers):"
echo "kubectl describe pod \$(kubectl get pods -l app=httpd -o jsonpath='{.items[0].metadata.name}')"
echo ""
echo "# Access Envoy admin interface:"
echo "kubectl port-forward \$(kubectl get pods -l app=httpd -o jsonpath='{.items[0].metadata.name}') 15000:15000"
echo "# Then visit: http://localhost:15000"
echo ""
echo "# View Istio proxy configuration:"
echo "istioctl proxy-config cluster \$(kubectl get pods -l app=httpd -o jsonpath='{.items[0].metadata.name}')"
echo ""
echo "# Open Kiali dashboard:"
echo "istioctl dashboard kiali"
echo ""
echo "# Open Grafana dashboard:"
echo "istioctl dashboard grafana"
echo ""
echo "# Open Jaeger tracing:"
echo "istioctl dashboard jaeger"
echo ""
echo "# Generate some traffic for testing:"
echo "for i in {1..100}; do curl -s http://\$GATEWAY_URL/ > /dev/null; echo \"Request \$i sent\"; sleep 1; done"

print_header "10. Cleanup (when done)"
echo ""
echo "To remove the demo:"
echo "./cleanup.sh"

echo ""
print_status "🎉 Deployment completed successfully!"
print_status "Your Apache HTTPD application is now running with Istio sidecar pattern"

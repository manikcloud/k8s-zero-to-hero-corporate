#!/bin/bash

# Kubernetes Sidecar Pattern Demo - Cleanup Script
# This script removes all resources created by the demo

set -e

echo "🧹 Cleaning up Sidecar Pattern Demo"
echo "==================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

print_status "Removing application resources..."
kubectl delete -f httpd-deployment.yaml --ignore-not-found=true
kubectl delete -f httpd-service.yaml --ignore-not-found=true

print_status "Removing Istio configuration..."
kubectl delete -f istio-gateway.yaml --ignore-not-found=true
kubectl delete -f istio-security.yaml --ignore-not-found=true

print_status "Removing sidecar injection label from default namespace..."
kubectl label namespace default istio-injection- --ignore-not-found=true

print_status "Checking remaining resources..."
kubectl get pods -l app=httpd
kubectl get services -l app=httpd

echo ""
print_warning "Note: Istio control plane is still installed."
print_warning "To completely remove Istio, run:"
echo "istioctl uninstall --purge -y"
echo "kubectl delete namespace istio-system"

print_status "🎉 Cleanup completed!"

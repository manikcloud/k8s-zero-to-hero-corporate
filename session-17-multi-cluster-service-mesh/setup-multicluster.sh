#!/bin/bash

# Multi-Cluster Kubernetes & Service Mesh Setup Script
# This script automates the setup of multi-cluster Kubernetes with Istio service mesh federation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
PRIMARY_CLUSTER="primary"
REMOTE_CLUSTER="remote"
MESH_ID="mesh1"
PRIMARY_NETWORK="network1"
REMOTE_NETWORK="network2"
NAMESPACE="sample"

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

print_success() {
    echo -e "${PURPLE}[SUCCESS]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
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
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        print_warning "helm is not installed. Please install Helm 3"
        exit 1
    fi
    
    # Check cluster contexts
    if ! kubectl config get-contexts | grep -q $PRIMARY_CLUSTER; then
        print_error "Primary cluster context '$PRIMARY_CLUSTER' not found"
        exit 1
    fi
    
    if ! kubectl config get-contexts | grep -q $REMOTE_CLUSTER; then
        print_error "Remote cluster context '$REMOTE_CLUSTER' not found"
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Function to setup certificates
setup_certificates() {
    print_header "Setting up Root Certificates"
    
    # Create certificates directory
    mkdir -p certs
    cd certs
    
    # Generate root certificate
    if [ ! -f root-cert.pem ]; then
        print_status "Generating root certificate..."
        
        # Create root key
        openssl genrsa -out root-key.pem 4096
        
        # Create root certificate
        openssl req -new -key root-key.pem -out root-cert.csr -config <(
        cat <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no
[req_distinguished_name]
C = US
ST = CA
L = San Francisco
O = Istio
OU = Multi-Cluster
CN = Root CA
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = istiod.istio-system.svc
DNS.2 = istiod.istio-system.svc.cluster.local
EOF
        )
        
        openssl x509 -req -days 3650 -in root-cert.csr -signkey root-key.pem -out root-cert.pem
        
        # Create intermediate certificates for each cluster
        for cluster in $PRIMARY_CLUSTER $REMOTE_CLUSTER; do
            # Generate intermediate key
            openssl genrsa -out ${cluster}-key.pem 4096
            
            # Generate intermediate certificate signing request
            openssl req -new -key ${cluster}-key.pem -out ${cluster}-cert.csr -config <(
            cat <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no
[req_distinguished_name]
C = US
ST = CA
L = San Francisco
O = Istio
OU = Multi-Cluster
CN = Intermediate CA ${cluster}
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = istiod.istio-system.svc
DNS.2 = istiod.istio-system.svc.cluster.local
EOF
            )
            
            # Sign intermediate certificate with root
            openssl x509 -req -days 3650 -in ${cluster}-cert.csr -CA root-cert.pem -CAkey root-key.pem -out ${cluster}-cert.pem -CAcreateserial
            
            # Create certificate chain
            cat ${cluster}-cert.pem root-cert.pem > ${cluster}-cert-chain.pem
        done
    fi
    
    cd ..
    print_success "Certificates setup completed"
}

# Function to install Istio on primary cluster
install_istio_primary() {
    print_header "Installing Istio on Primary Cluster"
    
    kubectl config use-context $PRIMARY_CLUSTER
    
    # Create istio-system namespace
    kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Create certificate secret
    kubectl create secret generic cacerts -n istio-system \
        --from-file=certs/root-cert.pem \
        --from-file=certs/${PRIMARY_CLUSTER}-cert-chain.pem \
        --from-file=certs/${PRIMARY_CLUSTER}-cert.pem \
        --from-file=certs/${PRIMARY_CLUSTER}-key.pem \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Istio
    istioctl install --set values.pilot.env.EXTERNAL_ISTIOD=true \
        --set values.global.meshID=${MESH_ID} \
        --set values.global.network=${PRIMARY_NETWORK} \
        --set values.istiod.env.EXTERNAL_ISTIOD=true \
        --set values.pilot.env.PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION=true \
        --set values.pilot.env.PILOT_ENABLE_CROSS_CLUSTER_WORKLOAD_ENTRY=true \
        --yes
    
    # Wait for Istio to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/istiod -n istio-system
    
    # Install east-west gateway
    kubectl apply -f manifests/istio-multicluster-config.yaml
    
    # Wait for east-west gateway
    kubectl wait --for=condition=available --timeout=300s deployment/istio-eastwestgateway -n istio-system
    
    print_success "Istio installed on primary cluster"
}

# Function to install Istio on remote cluster
install_istio_remote() {
    print_header "Installing Istio on Remote Cluster"
    
    kubectl config use-context $REMOTE_CLUSTER
    
    # Get discovery address from primary cluster
    kubectl config use-context $PRIMARY_CLUSTER
    DISCOVERY_ADDRESS=$(kubectl get svc istio-eastwestgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    
    if [ -z "$DISCOVERY_ADDRESS" ]; then
        DISCOVERY_ADDRESS=$(kubectl get svc istio-eastwestgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    fi
    
    if [ -z "$DISCOVERY_ADDRESS" ]; then
        print_warning "LoadBalancer IP/hostname not available. Using port-forward for local testing."
        kubectl port-forward -n istio-system svc/istio-eastwestgateway 15012:15012 &
        DISCOVERY_ADDRESS="localhost"
        sleep 5
    fi
    
    print_status "Discovery address: $DISCOVERY_ADDRESS"
    
    # Switch to remote cluster
    kubectl config use-context $REMOTE_CLUSTER
    
    # Create istio-system namespace
    kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Create certificate secret
    kubectl create secret generic cacerts -n istio-system \
        --from-file=certs/root-cert.pem \
        --from-file=certs/${REMOTE_CLUSTER}-cert-chain.pem \
        --from-file=certs/${REMOTE_CLUSTER}-cert.pem \
        --from-file=certs/${REMOTE_CLUSTER}-key.pem \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Istio on remote cluster
    istioctl install --set values.pilot.env.EXTERNAL_ISTIOD=true \
        --set values.global.meshID=${MESH_ID} \
        --set values.global.network=${REMOTE_NETWORK} \
        --set values.istiod.env.EXTERNAL_ISTIOD=true \
        --set values.pilot.env.PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION=true \
        --set values.pilot.env.PILOT_ENABLE_CROSS_CLUSTER_WORKLOAD_ENTRY=true \
        --set values.global.remotePilotAddress=${DISCOVERY_ADDRESS} \
        --yes
    
    # Wait for Istio to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/istiod -n istio-system
    
    print_success "Istio installed on remote cluster"
}

# Function to deploy applications
deploy_applications() {
    print_header "Deploying Sample Applications"
    
    # Deploy on primary cluster
    kubectl config use-context $PRIMARY_CLUSTER
    kubectl apply -f manifests/multi-cluster-setup.yaml
    
    # Wait for deployments
    kubectl wait --for=condition=available --timeout=300s deployment/helloworld-v1 -n $NAMESPACE
    kubectl wait --for=condition=available --timeout=300s deployment/sleep -n $NAMESPACE
    
    # Deploy on remote cluster
    kubectl config use-context $REMOTE_CLUSTER
    kubectl apply -f manifests/multi-cluster-setup.yaml
    
    # Wait for deployments
    kubectl wait --for=condition=available --timeout=300s deployment/helloworld-v2 -n $NAMESPACE
    kubectl wait --for=condition=available --timeout=300s deployment/sleep -n $NAMESPACE
    
    print_success "Applications deployed on both clusters"
}

# Function to configure cross-cluster service discovery
configure_service_discovery() {
    print_header "Configuring Cross-Cluster Service Discovery"
    
    # Apply service entries and traffic policies
    kubectl config use-context $PRIMARY_CLUSTER
    kubectl apply -f manifests/istio-multicluster-config.yaml
    
    kubectl config use-context $REMOTE_CLUSTER
    kubectl apply -f manifests/istio-multicluster-config.yaml
    
    print_success "Cross-cluster service discovery configured"
}

# Function to test connectivity
test_connectivity() {
    print_header "Testing Cross-Cluster Connectivity"
    
    # Test from primary cluster
    kubectl config use-context $PRIMARY_CLUSTER
    SLEEP_POD=$(kubectl get pod -l app=sleep -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
    
    print_status "Testing from primary cluster:"
    for i in {1..5}; do
        result=$(kubectl exec -n $NAMESPACE $SLEEP_POD -c sleep -- curl -s helloworld.sample.global:5000/hello 2>/dev/null || echo "Failed")
        echo "  Request $i: $result"
    done
    
    # Test from remote cluster
    kubectl config use-context $REMOTE_CLUSTER
    SLEEP_POD=$(kubectl get pod -l app=sleep -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
    
    print_status "Testing from remote cluster:"
    for i in {1..5}; do
        result=$(kubectl exec -n $NAMESPACE $SLEEP_POD -c sleep -- curl -s helloworld.sample.global:5000/hello 2>/dev/null || echo "Failed")
        echo "  Request $i: $result"
    done
    
    print_success "Connectivity test completed"
}

# Function to install monitoring
install_monitoring() {
    print_header "Installing Monitoring Stack"
    
    kubectl config use-context $PRIMARY_CLUSTER
    
    # Install Prometheus
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/prometheus.yaml
    
    # Install Grafana
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/grafana.yaml
    
    # Install Kiali
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/kiali.yaml
    
    # Wait for deployments
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n istio-system
    kubectl wait --for=condition=available --timeout=300s deployment/grafana -n istio-system
    kubectl wait --for=condition=available --timeout=300s deployment/kiali -n istio-system
    
    print_success "Monitoring stack installed"
}

# Function to display access information
display_access_info() {
    print_header "Access Information"
    
    kubectl config use-context $PRIMARY_CLUSTER
    
    print_status "To access monitoring dashboards, run the following commands:"
    echo ""
    echo "# Kiali Dashboard:"
    echo "kubectl port-forward -n istio-system svc/kiali 20001:20001"
    echo "# Then visit: http://localhost:20001"
    echo ""
    echo "# Grafana Dashboard:"
    echo "kubectl port-forward -n istio-system svc/grafana 3000:3000"
    echo "# Then visit: http://localhost:3000"
    echo ""
    echo "# Prometheus:"
    echo "kubectl port-forward -n istio-system svc/prometheus 9090:9090"
    echo "# Then visit: http://localhost:9090"
    echo ""
    
    print_status "To test cross-cluster communication:"
    echo ""
    echo "# Switch to primary cluster:"
    echo "kubectl config use-context $PRIMARY_CLUSTER"
    echo ""
    echo "# Test connectivity:"
    echo "SLEEP_POD=\$(kubectl get pod -l app=sleep -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')"
    echo "kubectl exec -n $NAMESPACE \$SLEEP_POD -c sleep -- curl helloworld.sample.global:5000/hello"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Multi-Cluster Kubernetes Setup Script${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    check_prerequisites
    setup_certificates
    install_istio_primary
    install_istio_remote
    deploy_applications
    configure_service_discovery
    test_connectivity
    install_monitoring
    display_access_info
    
    echo ""
    print_success "🎉 Multi-cluster setup completed successfully!"
    print_status "Your multi-cluster Kubernetes environment with Istio service mesh is ready!"
}

# Run main function
main "$@"

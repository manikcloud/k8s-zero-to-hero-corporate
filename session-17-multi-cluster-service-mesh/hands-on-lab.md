# Hands-on Lab: Multi-Cluster Kubernetes & Service Mesh Federation

## 🎯 **Lab Objectives**

By completing this lab, you will:
- Set up a multi-cluster Kubernetes environment
- Configure Istio service mesh federation
- Implement cross-cluster service communication
- Test failover and load balancing scenarios
- Monitor multi-cluster deployments

---

## 🛠 **Prerequisites**

- Two Kubernetes clusters (can be local with kind/minikube)
- kubectl configured with contexts for both clusters
- Istio CLI (istioctl) installed
- Helm 3 installed
- Basic understanding of Istio concepts

---

## 📋 **Lab Environment Setup**

### Step 1: Create Two Kubernetes Clusters

#### Option A: Using kind (Local Development)
```bash
# Create primary cluster
cat <<EOF | kind create cluster --name primary --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "cluster=primary"
- role: worker
- role: worker
networking:
  podSubnet: "10.1.0.0/16"
  serviceSubnet: "10.2.0.0/16"
EOF

# Create remote cluster
cat <<EOF | kind create cluster --name remote --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "cluster=remote"
- role: worker
- role: worker
networking:
  podSubnet: "10.3.0.0/16"
  serviceSubnet: "10.4.0.0/16"
EOF
```

#### Option B: Using Cloud Providers
```bash
# AWS EKS
eksctl create cluster --name primary --region us-east-1 --nodes 3
eksctl create cluster --name remote --region us-west-2 --nodes 3

# GCP GKE
gcloud container clusters create primary --zone us-central1-a --num-nodes 3
gcloud container clusters create remote --zone us-west1-a --num-nodes 3

# Azure AKS
az aks create --resource-group myResourceGroup --name primary --node-count 3
az aks create --resource-group myResourceGroup --name remote --node-count 3
```

### Step 2: Configure kubectl Contexts

```bash
# List available contexts
kubectl config get-contexts

# Rename contexts for clarity
kubectl config rename-context kind-primary primary
kubectl config rename-context kind-remote remote

# Verify contexts
kubectl config get-contexts
```

---

## 🔧 **Istio Multi-Cluster Setup**

### Step 3: Install Istio on Primary Cluster

```bash
# Switch to primary cluster
kubectl config use-context primary

# Set environment variables
export CLUSTER_NAME=primary
export CLUSTER_NETWORK=network1
export MESH_ID=mesh1

# Install Istio
istioctl install --set values.pilot.env.EXTERNAL_ISTIOD=true \
  --set values.global.meshID=${MESH_ID} \
  --set values.global.network=${CLUSTER_NETWORK} \
  --set values.istiod.env.EXTERNAL_ISTIOD=true \
  --set values.pilot.env.PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION=true \
  --set values.pilot.env.PILOT_ENABLE_CROSS_CLUSTER_WORKLOAD_ENTRY=true

# Verify installation
kubectl get pods -n istio-system
istioctl verify-install
```

### Step 4: Install East-West Gateway

```bash
# Install east-west gateway for cross-cluster communication
kubectl apply -f - <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: eastwest
spec:
  revision: ""
  components:
    ingressGateways:
      - name: istio-eastwestgateway
        label:
          istio: eastwestgateway
          app: istio-eastwestgateway
        enabled: true
        k8s:
          service:
            type: LoadBalancer
            ports:
              - port: 15021
                targetPort: 15021
                name: status-port
              - port: 15012
                targetPort: 15012
                name: tls
              - port: 15017
                targetPort: 15017
                name: tls-istiod
EOF

# Wait for LoadBalancer IP
kubectl wait --for=condition=ready pod -l istio=eastwestgateway -n istio-system --timeout=300s

# Get the external IP
export DISCOVERY_ADDRESS=$(kubectl get svc istio-eastwestgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Discovery Address: $DISCOVERY_ADDRESS"

# If using kind, use port-forward instead
if [ -z "$DISCOVERY_ADDRESS" ]; then
  kubectl port-forward -n istio-system svc/istio-eastwestgateway 15012:15012 &
  export DISCOVERY_ADDRESS=localhost
fi
```

### Step 5: Configure Cross-Cluster Access

```bash
# Create secret for cross-cluster access
kubectl create secret generic cacerts -n istio-system \
  --from-file=root-cert.pem \
  --from-file=cert-chain.pem \
  --from-file=ca-cert.pem \
  --from-file=ca-key.pem

# Create namespace and label for cross-cluster services
kubectl create namespace sample
kubectl label namespace sample istio-injection=enabled

# Apply gateway configuration for cross-cluster access
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: cross-network-gateway
  namespace: istio-system
spec:
  selector:
    istio: eastwestgateway
  servers:
    - port:
        number: 15012
        name: tls
        protocol: TLS
      tls:
        mode: ISTIO_MUTUAL
      hosts:
        - "*.local"
EOF
```

### Step 6: Install Istio on Remote Cluster

```bash
# Switch to remote cluster
kubectl config use-context remote

# Set environment variables for remote cluster
export CLUSTER_NAME=remote
export CLUSTER_NETWORK=network2
export MESH_ID=mesh1

# Install Istio on remote cluster
istioctl install --set values.pilot.env.EXTERNAL_ISTIOD=true \
  --set values.global.meshID=${MESH_ID} \
  --set values.global.network=${CLUSTER_NETWORK} \
  --set values.istiod.env.EXTERNAL_ISTIOD=true \
  --set values.pilot.env.PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION=true \
  --set values.pilot.env.PILOT_ENABLE_CROSS_CLUSTER_WORKLOAD_ENTRY=true \
  --set values.global.remotePilotAddress=${DISCOVERY_ADDRESS}

# Create the same secret on remote cluster
kubectl create secret generic cacerts -n istio-system \
  --from-file=root-cert.pem \
  --from-file=cert-chain.pem \
  --from-file=ca-cert.pem \
  --from-file=ca-key.pem

# Create namespace
kubectl create namespace sample
kubectl label namespace sample istio-injection=enabled
```

---

## 🚀 **Deploy Sample Applications**

### Step 7: Deploy Application on Primary Cluster

```bash
# Switch to primary cluster
kubectl config use-context primary

# Deploy HelloWorld v1
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld-v1
  namespace: sample
  labels:
    app: helloworld
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: helloworld
      version: v1
  template:
    metadata:
      labels:
        app: helloworld
        version: v1
    spec:
      containers:
      - name: helloworld
        image: docker.io/istio/examples-helloworld-v1
        resources:
          requests:
            cpu: "100m"
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 5000
---
apiVersion: v1
kind: Service
metadata:
  name: helloworld
  namespace: sample
  labels:
    app: helloworld
    service: helloworld
spec:
  ports:
  - port: 5000
    name: http
  selector:
    app: helloworld
EOF

# Verify deployment
kubectl get pods -n sample
kubectl get svc -n sample
```

### Step 8: Deploy Application on Remote Cluster

```bash
# Switch to remote cluster
kubectl config use-context remote

# Deploy HelloWorld v2
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld-v2
  namespace: sample
  labels:
    app: helloworld
    version: v2
spec:
  replicas: 2
  selector:
    matchLabels:
      app: helloworld
      version: v2
  template:
    metadata:
      labels:
        app: helloworld
        version: v2
    spec:
      containers:
      - name: helloworld
        image: docker.io/istio/examples-helloworld-v2
        resources:
          requests:
            cpu: "100m"
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 5000
---
apiVersion: v1
kind: Service
metadata:
  name: helloworld
  namespace: sample
  labels:
    app: helloworld
    service: helloworld
spec:
  ports:
  - port: 5000
    name: http
  selector:
    app: helloworld
EOF

# Verify deployment
kubectl get pods -n sample
kubectl get svc -n sample
```

---

## 🔗 **Configure Cross-Cluster Service Discovery**

### Step 9: Create Cross-Cluster Service Entries

```bash
# On primary cluster - register remote cluster services
kubectl config use-context primary

kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: helloworld-remote
  namespace: sample
spec:
  hosts:
  - helloworld.sample.global
  location: MESH_EXTERNAL
  ports:
  - number: 5000
    name: http
    protocol: HTTP
  resolution: DNS
  addresses:
  - 240.0.0.1
  endpoints:
  - address: helloworld.sample.svc.cluster.local
    network: network2
    ports:
      http: 5000
EOF

# On remote cluster - register primary cluster services
kubectl config use-context remote

kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: helloworld-primary
  namespace: sample
spec:
  hosts:
  - helloworld.sample.global
  location: MESH_EXTERNAL
  ports:
  - number: 5000
    name: http
    protocol: HTTP
  resolution: DNS
  addresses:
  - 240.0.0.2
  endpoints:
  - address: helloworld.sample.svc.cluster.local
    network: network1
    ports:
      http: 5000
EOF
```

### Step 10: Deploy Sleep Pod for Testing

```bash
# Deploy sleep pod on both clusters for testing
for cluster in primary remote; do
  kubectl config use-context $cluster
  kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sleep
  namespace: sample
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sleep
  template:
    metadata:
      labels:
        app: sleep
    spec:
      containers:
      - name: sleep
        image: curlimages/curl
        command: ["/bin/sleep", "infinity"]
        imagePullPolicy: IfNotPresent
EOF
done
```

---

## 🧪 **Testing Cross-Cluster Communication**

### Step 11: Test Cross-Cluster Connectivity

```bash
# Test from primary cluster
kubectl config use-context primary

# Get sleep pod name
SLEEP_POD=$(kubectl get pod -l app=sleep -n sample -o jsonpath='{.items[0].metadata.name}')

# Test local service
echo "Testing local service (should return v1):"
kubectl exec -n sample $SLEEP_POD -c sleep -- curl -s helloworld.sample:5000/hello

# Test cross-cluster service
echo "Testing cross-cluster service (should return v1 and v2):"
for i in {1..10}; do
  kubectl exec -n sample $SLEEP_POD -c sleep -- curl -s helloworld.sample.global:5000/hello
done

# Test from remote cluster
kubectl config use-context remote

SLEEP_POD=$(kubectl get pod -l app=sleep -n sample -o jsonpath='{.items[0].metadata.name}')

echo "Testing from remote cluster:"
for i in {1..10}; do
  kubectl exec -n sample $SLEEP_POD -c sleep -- curl -s helloworld.sample.global:5000/hello
done
```

### Step 12: Configure Traffic Policies

```bash
# Apply DestinationRule for load balancing
kubectl config use-context primary

kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: helloworld-destination-rule
  namespace: sample
spec:
  host: helloworld.sample.global
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
    loadBalancer:
      simple: ROUND_ROBIN
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: helloworld-virtual-service
  namespace: sample
spec:
  hosts:
  - helloworld.sample.global
  http:
  - match:
    - headers:
        version:
          exact: v2
    route:
    - destination:
        host: helloworld.sample.global
        subset: v2
  - route:
    - destination:
        host: helloworld.sample.global
        subset: v1
      weight: 50
    - destination:
        host: helloworld.sample.global
        subset: v2
      weight: 50
EOF
```

---

## 📊 **Monitoring and Observability**

### Step 13: Install Monitoring Stack

```bash
# Install Prometheus on primary cluster
kubectl config use-context primary

kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/prometheus.yaml

# Install Grafana
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/grafana.yaml

# Install Kiali
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/kiali.yaml

# Wait for deployments
kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n istio-system
kubectl wait --for=condition=available --timeout=300s deployment/grafana -n istio-system
kubectl wait --for=condition=available --timeout=300s deployment/kiali -n istio-system
```

### Step 14: Access Monitoring Dashboards

```bash
# Open Kiali dashboard
kubectl port-forward -n istio-system svc/kiali 20001:20001 &
echo "Kiali: http://localhost:20001"

# Open Grafana dashboard
kubectl port-forward -n istio-system svc/grafana 3000:3000 &
echo "Grafana: http://localhost:3000"

# Open Prometheus
kubectl port-forward -n istio-system svc/prometheus 9090:9090 &
echo "Prometheus: http://localhost:9090"
```

### Step 15: Generate Traffic for Monitoring

```bash
# Generate continuous traffic
kubectl config use-context primary

SLEEP_POD=$(kubectl get pod -l app=sleep -n sample -o jsonpath='{.items[0].metadata.name}')

# Run traffic generation in background
kubectl exec -n sample $SLEEP_POD -c sleep -- sh -c '
while true; do
  curl -s helloworld.sample.global:5000/hello
  sleep 1
done' &

# Generate traffic with different headers
kubectl exec -n sample $SLEEP_POD -c sleep -- sh -c '
while true; do
  curl -s -H "version: v2" helloworld.sample.global:5000/hello
  sleep 2
done' &
```

---

## 🔧 **Failure Testing**

### Step 16: Test Cluster Failover

```bash
# Scale down v1 deployment on primary cluster
kubectl config use-context primary
kubectl scale deployment helloworld-v1 --replicas=0 -n sample

# Test traffic - should only return v2 responses
SLEEP_POD=$(kubectl get pod -l app=sleep -n sample -o jsonpath='{.items[0].metadata.name}')
for i in {1..10}; do
  kubectl exec -n sample $SLEEP_POD -c sleep -- curl -s helloworld.sample.global:5000/hello
done

# Scale back up
kubectl scale deployment helloworld-v1 --replicas=2 -n sample
```

### Step 17: Test Network Partitioning

```bash
# Simulate network partition by blocking traffic
kubectl config use-context primary

# Create network policy to block cross-cluster traffic
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-cross-cluster
  namespace: sample
spec:
  podSelector:
    matchLabels:
      app: helloworld
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: sample
    ports:
    - protocol: TCP
      port: 5000
EOF

# Test traffic - should only return local responses
SLEEP_POD=$(kubectl get pod -l app=sleep -n sample -o jsonpath='{.items[0].metadata.name}')
for i in {1..10}; do
  kubectl exec -n sample $SLEEP_POD -c sleep -- curl -s helloworld.sample.global:5000/hello
done

# Remove network policy
kubectl delete networkpolicy block-cross-cluster -n sample
```

---

## 🔍 **Troubleshooting**

### Step 18: Debugging Cross-Cluster Issues

```bash
# Check Istio proxy configuration
kubectl config use-context primary
HELLOWORLD_POD=$(kubectl get pod -l app=helloworld,version=v1 -n sample -o jsonpath='{.items[0].metadata.name}')

# Check clusters configuration
istioctl proxy-config cluster $HELLOWORLD_POD.sample

# Check endpoints
istioctl proxy-config endpoints $HELLOWORLD_POD.sample

# Check listeners
istioctl proxy-config listeners $HELLOWORLD_POD.sample

# Check routes
istioctl proxy-config routes $HELLOWORLD_POD.sample

# Check secrets (certificates)
istioctl proxy-config secret $HELLOWORLD_POD.sample
```

### Step 19: Verify Service Discovery

```bash
# Check service registry
kubectl config use-context primary
istioctl proxy-status

# Check cross-cluster endpoints
kubectl get endpoints helloworld -n sample -o yaml

# Verify DNS resolution
SLEEP_POD=$(kubectl get pod -l app=sleep -n sample -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n sample $SLEEP_POD -c sleep -- nslookup helloworld.sample.global
```

---

## 🧹 **Cleanup**

### Step 20: Clean Up Resources

```bash
# Clean up applications
for cluster in primary remote; do
  kubectl config use-context $cluster
  kubectl delete namespace sample
done

# Clean up Istio
kubectl config use-context primary
istioctl uninstall --purge -y
kubectl delete namespace istio-system

kubectl config use-context remote
istioctl uninstall --purge -y
kubectl delete namespace istio-system

# Delete clusters (if using kind)
kind delete cluster --name primary
kind delete cluster --name remote
```

---

## 🎓 **Lab Verification Checklist**

- [ ] Two Kubernetes clusters created and accessible
- [ ] Istio installed on both clusters with multi-cluster configuration
- [ ] Cross-cluster service discovery working
- [ ] Applications deployed on both clusters
- [ ] Cross-cluster communication established
- [ ] Traffic policies applied and working
- [ ] Monitoring dashboards accessible and showing data
- [ ] Failover scenarios tested successfully
- [ ] Network policies tested
- [ ] Troubleshooting commands executed

---

## 📚 **Key Takeaways**

1. **Multi-cluster setup requires careful network planning**
2. **Service mesh federation enables seamless cross-cluster communication**
3. **Proper certificate management is crucial for security**
4. **Monitoring becomes more complex but more important**
5. **Failure testing is essential for production readiness**

---

## 🔗 **Additional Resources**

- [Istio Multi-Cluster Documentation](https://istio.io/latest/docs/setup/install/multicluster/)
- [Kubernetes Multi-Cluster Networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [Service Mesh Federation Patterns](https://www.cncf.io/blog/2021/04/12/service-mesh-federation/)

This hands-on lab provides practical experience with multi-cluster Kubernetes and service mesh federation, essential skills for enterprise-scale deployments.

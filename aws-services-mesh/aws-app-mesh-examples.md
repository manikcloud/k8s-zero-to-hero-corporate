# AWS App Mesh - Practical Implementation Examples

## 🚀 **Complete AWS App Mesh Setup Guide**

### Prerequisites
- EKS cluster running
- AWS CLI configured
- kubectl configured
- Helm 3 installed

---

## 📋 **Step 1: Install App Mesh Controller**

```bash
# Add EKS Helm repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Create namespace
kubectl create namespace appmesh-system

# Install App Mesh Controller
helm install appmesh-controller eks/appmesh-controller \
    --namespace appmesh-system \
    --set region=us-west-2 \
    --set serviceAccount.create=false \
    --set serviceAccount.name=appmesh-controller
```

### Create IAM Service Account
```bash
# Create IAM service account for App Mesh
eksctl create iamserviceaccount \
    --cluster=my-cluster \
    --namespace=appmesh-system \
    --name=appmesh-controller \
    --attach-policy-arn=arn:aws:iam::aws:policy/AWSCloudMapFullAccess \
    --attach-policy-arn=arn:aws:iam::aws:policy/AWSAppMeshFullAccess \
    --override-existing-serviceaccounts \
    --approve
```

---

## 🏗 **Step 2: Create App Mesh Resources**

### Mesh Definition
```yaml
apiVersion: appmesh.k8s.aws/v1beta2
kind: Mesh
metadata:
  name: e-commerce-mesh
spec:
  namespaceSelector:
    matchLabels:
      mesh: e-commerce
  meshOwner: "123456789012"  # Your AWS Account ID
```

### Virtual Gateway
```yaml
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualGateway
metadata:
  name: ingress-gateway
  namespace: default
spec:
  namespaceSelector:
    matchLabels:
      gateway: ingress
  meshRef:
    name: e-commerce-mesh
    uid: a385048d-ebe7-4c5a-abad-6e694d6bd93d
  listeners:
    - portMapping:
        port: 8080
        protocol: http
  logging:
    accessLog:
      file:
        path: /dev/stdout
```

### Virtual Service
```yaml
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualService
metadata:
  name: product-service
  namespace: default
spec:
  meshRef:
    name: e-commerce-mesh
    uid: a385048d-ebe7-4c5a-abad-6e694d6bd93d
  provider:
    virtualRouter:
      virtualRouterRef:
        name: product-router
```

### Virtual Router
```yaml
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualRouter
metadata:
  name: product-router
  namespace: default
spec:
  meshRef:
    name: e-commerce-mesh
    uid: a385048d-ebe7-4c5a-abad-6e694d6bd93d
  listeners:
    - portMapping:
        port: 8080
        protocol: http
  routes:
    - name: product-route
      httpRoute:
        match:
          prefix: /
        action:
          weightedTargets:
            - virtualNodeRef:
                name: product-service-v1
              weight: 90
            - virtualNodeRef:
                name: product-service-v2
              weight: 10
        retryPolicy:
          maxRetries: 3
          perRetryTimeout:
            unit: s
            value: 2
          httpRetryEvents:
            - server-error
            - client-error
            - gateway-error
```

### Virtual Node
```yaml
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualNode
metadata:
  name: product-service-v1
  namespace: default
spec:
  meshRef:
    name: e-commerce-mesh
    uid: a385048d-ebe7-4c5a-abad-6e694d6bd93d
  podSelector:
    matchLabels:
      app: product-service
      version: v1
  listeners:
    - portMapping:
        port: 8080
        protocol: http
      healthCheck:
        protocol: http
        path: '/health'
        healthyThreshold: 2
        unhealthyThreshold: 2
        timeoutMillis: 2000
        intervalMillis: 5000
      tls:
        mode: STRICT
        certificate:
          acm:
            certificateArn: arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012
  serviceDiscovery:
    dns:
      hostname: product-service.default.svc.cluster.local
  backends:
    - virtualService:
        virtualServiceRef:
          name: database-service
    - virtualService:
        virtualServiceRef:
          name: cache-service
  logging:
    accessLog:
      file:
        path: /dev/stdout
```

---

## 🛠 **Step 3: Deploy Application with App Mesh**

### Product Service Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-service-v1
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: product-service
      version: v1
  template:
    metadata:
      labels:
        app: product-service
        version: v1
      annotations:
        appmesh.k8s.aws/mesh: e-commerce-mesh
    spec:
      serviceAccountName: product-service
      containers:
      - name: product-service
        image: my-account.dkr.ecr.us-west-2.amazonaws.com/product-service:v1
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          value: "database-service.default.svc.cluster.local:5432"
        - name: CACHE_URL
          value: "cache-service.default.svc.cluster.local:6379"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

### Service Definition
```yaml
apiVersion: v1
kind: Service
metadata:
  name: product-service
  namespace: default
  labels:
    app: product-service
spec:
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: product-service
  type: ClusterIP
```

---

## 🔒 **Step 4: Security Configuration**

### IAM Role for Service Account
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: product-service
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/ProductServiceRole
```

### IAM Policy for Product Service
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "appmesh:StreamAggregatedResources"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "acm:ExportCertificate",
                "acm:DescribeCertificate"
            ],
            "Resource": "arn:aws:acm:*:123456789012:certificate/*"
        }
    ]
}
```

### TLS Configuration
```yaml
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualNode
metadata:
  name: secure-service
spec:
  meshRef:
    name: e-commerce-mesh
  listeners:
    - portMapping:
        port: 8080
        protocol: http
      tls:
        mode: STRICT
        certificate:
          acm:
            certificateArn: arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012
        validation:
          trust:
            acm:
              certificateAuthorityArns:
                - arn:aws:acm-pca:us-west-2:123456789012:certificate-authority/12345678-1234-1234-1234-123456789012
```

---

## 📊 **Step 5: Observability Setup**

### CloudWatch Configuration
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: amazon-cloudwatch
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush         1
        Log_Level     info
        Daemon        off
        Parsers_File  parsers.conf
        HTTP_Server   On
        HTTP_Listen   0.0.0.0
        HTTP_Port     2020

    [INPUT]
        Name              tail
        Tag               application.*
        Path              /var/log/containers/*product-service*.log
        Parser            docker
        DB                /var/log/flb_kube.db
        Mem_Buf_Limit     50MB
        Skip_Long_Lines   On
        Refresh_Interval  10

    [OUTPUT]
        Name                cloudwatch_logs
        Match               application.*
        region              us-west-2
        log_group_name      /aws/containerinsights/my-cluster/application
        log_stream_prefix   product-service-
        auto_create_group   true
```

### X-Ray Tracing
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: xray-daemon
  namespace: default
spec:
  selector:
    matchLabels:
      app: xray-daemon
  template:
    metadata:
      labels:
        app: xray-daemon
    spec:
      serviceAccountName: xray-daemon
      containers:
      - name: xray-daemon
        image: amazon/aws-xray-daemon:latest
        command:
        - /usr/bin/xray
        - -o
        - -b
        - 0.0.0.0:2000
        resources:
          requests:
            memory: "32Mi"
            cpu: "128m"
          limits:
            memory: "256Mi"
            cpu: "256m"
        ports:
        - containerPort: 2000
          protocol: UDP
```

---

## 🔄 **Step 6: Traffic Management**

### Canary Deployment
```yaml
# Update Virtual Router for canary deployment
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualRouter
metadata:
  name: product-router
spec:
  routes:
    - name: product-canary-route
      httpRoute:
        match:
          prefix: /
          headers:
            - name: canary
              match:
                exact: "true"
        action:
          weightedTargets:
            - virtualNodeRef:
                name: product-service-v2
              weight: 100
    - name: product-main-route
      httpRoute:
        match:
          prefix: /
        action:
          weightedTargets:
            - virtualNodeRef:
                name: product-service-v1
              weight: 90
            - virtualNodeRef:
                name: product-service-v2
              weight: 10
```

### Circuit Breaker Configuration
```yaml
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualNode
metadata:
  name: product-service-v1
spec:
  backends:
    - virtualService:
        virtualServiceRef:
          name: database-service
        clientPolicy:
          tls:
            enforce: true
            ports:
              - 5432
            validation:
              trust:
                acm:
                  certificateAuthorityArns:
                    - arn:aws:acm-pca:us-west-2:123456789012:certificate-authority/12345678-1234-1234-1234-123456789012
```

---

## 🧪 **Step 7: Testing and Validation**

### Deployment Script
```bash
#!/bin/bash

# Deploy App Mesh resources
echo "Deploying App Mesh resources..."
kubectl apply -f mesh.yaml
kubectl apply -f virtual-gateway.yaml
kubectl apply -f virtual-service.yaml
kubectl apply -f virtual-router.yaml
kubectl apply -f virtual-node.yaml

# Wait for resources to be ready
echo "Waiting for App Mesh resources..."
kubectl wait --for=condition=MeshActive mesh/e-commerce-mesh --timeout=300s

# Deploy application
echo "Deploying application..."
kubectl apply -f product-service-deployment.yaml
kubectl apply -f product-service-service.yaml

# Wait for deployment
kubectl wait --for=condition=available --timeout=300s deployment/product-service-v1

# Verify deployment
echo "Verifying deployment..."
kubectl get pods -l app=product-service
kubectl get mesh,virtualservice,virtualnode,virtualrouter

# Test connectivity
echo "Testing connectivity..."
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v http://product-service.default.svc.cluster.local:8080/health
```

### Health Check Script
```bash
#!/bin/bash

# Check App Mesh Controller
echo "Checking App Mesh Controller..."
kubectl get pods -n appmesh-system

# Check mesh status
echo "Checking mesh status..."
aws appmesh describe-mesh --mesh-name e-commerce-mesh

# Check virtual services
echo "Checking virtual services..."
aws appmesh list-virtual-services --mesh-name e-commerce-mesh

# Check Envoy proxy status
echo "Checking Envoy proxy status..."
kubectl exec -it $(kubectl get pod -l app=product-service -o jsonpath='{.items[0].metadata.name}') \
  -c envoy -- curl -s http://localhost:9901/stats | grep -E "(health_check|circuit_breaker)"

# Check CloudWatch metrics
echo "Checking CloudWatch metrics..."
aws cloudwatch get-metric-statistics \
  --namespace AWS/AppMesh \
  --metric-name RequestCount \
  --dimensions Name=MeshName,Value=e-commerce-mesh \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

---

## 🔧 **Troubleshooting Common Issues**

### Issue 1: Envoy Sidecar Not Injected
```bash
# Check if namespace has mesh label
kubectl get namespace default --show-labels

# Add mesh label if missing
kubectl label namespace default mesh=e-commerce

# Check App Mesh Controller logs
kubectl logs -n appmesh-system deployment/appmesh-controller

# Restart deployment to trigger injection
kubectl rollout restart deployment/product-service-v1
```

### Issue 2: Service Discovery Issues
```bash
# Check virtual node configuration
kubectl describe virtualnode product-service-v1

# Verify service exists
kubectl get service product-service

# Check DNS resolution
kubectl run debug-pod --image=busybox --rm -it --restart=Never -- \
  nslookup product-service.default.svc.cluster.local

# Check Envoy cluster configuration
kubectl exec -it $(kubectl get pod -l app=product-service -o jsonpath='{.items[0].metadata.name}') \
  -c envoy -- curl -s http://localhost:9901/clusters
```

### Issue 3: TLS Certificate Issues
```bash
# Check ACM certificate status
aws acm describe-certificate --certificate-arn arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012

# Check Envoy certificate configuration
kubectl exec -it $(kubectl get pod -l app=product-service -o jsonpath='{.items[0].metadata.name}') \
  -c envoy -- curl -s http://localhost:9901/certs

# Verify IAM permissions
aws sts get-caller-identity
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/ProductServiceRole \
  --action-names acm:ExportCertificate \
  --resource-arns arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012
```

---

## 📈 **Performance Optimization**

### Envoy Resource Tuning
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy-config
data:
  envoy.yaml: |
    admin:
      access_log_path: /tmp/admin_access.log
      address:
        socket_address:
          protocol: TCP
          address: 127.0.0.1
          port_value: 9901
    static_resources:
      clusters:
      - name: product_service
        connect_timeout: 0.25s
        type: LOGICAL_DNS
        dns_lookup_family: V4_ONLY
        lb_policy: ROUND_ROBIN
        circuit_breakers:
          thresholds:
          - priority: DEFAULT
            max_connections: 100
            max_pending_requests: 100
            max_requests: 100
            max_retries: 3
        outlier_detection:
          consecutive_5xx: 3
          interval: 30s
          base_ejection_time: 30s
          max_ejection_percent: 50
```

### Resource Limits
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-service-v1
spec:
  template:
    spec:
      containers:
      - name: envoy
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      - name: product-service
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

---

## 🎯 **Best Practices Summary**

1. **Use IAM roles for service accounts** for secure AWS service access
2. **Enable TLS everywhere** using ACM certificates
3. **Implement proper health checks** for reliable service discovery
4. **Use CloudWatch and X-Ray** for comprehensive observability
5. **Configure circuit breakers** to prevent cascade failures
6. **Implement gradual rollouts** using weighted routing
7. **Monitor resource usage** and optimize Envoy configuration
8. **Use proper labeling** for service mesh organization
9. **Implement retry policies** for resilient communication
10. **Regular security audits** of mesh configuration

---

This comprehensive guide provides everything needed to implement AWS App Mesh in a production environment with proper security, observability, and performance optimization.

# Session 12: Security, RBAC & Best Practices

## 🎯 **Session Objectives**
By the end of this session, you will be able to:
- Implement comprehensive Role-Based Access Control (RBAC)
- Configure Pod Security Policies and Pod Security Standards
- Secure container images and implement vulnerability scanning
- Deploy network policies for microsegmentation
- Apply security compliance frameworks and audit strategies

## 📖 **Theoretical Foundation**

### **Kubernetes Security Model**
Kubernetes security operates on multiple layers:
1. **Cluster Security**: API server, etcd encryption, network policies
2. **Node Security**: Container runtime, kernel security, host hardening
3. **Pod Security**: Security contexts, admission controllers, policies
4. **Application Security**: Image scanning, secrets management, RBAC

### **RBAC Components**
- **Subjects**: Users, Groups, ServiceAccounts
- **Resources**: Pods, Services, ConfigMaps, etc.
- **Verbs**: get, list, create, update, delete, watch
- **Roles**: Define permissions within a namespace
- **ClusterRoles**: Define cluster-wide permissions

## 🔧 **Hands-on Labs**

### **Lab 1: RBAC Implementation**
```bash
# Create security namespace
kubectl create namespace security-lab

# Create ServiceAccount
kubectl create serviceaccount developer-sa -n security-lab

# Create Role with specific permissions
cat > developer-role.yaml << 'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: security-lab
  name: developer-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "create", "update", "patch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "patch"]
YAML

kubectl apply -f developer-role.yaml

# Create RoleBinding
kubectl create rolebinding developer-binding \
  --role=developer-role \
  --serviceaccount=security-lab:developer-sa \
  -n security-lab

# Test RBAC permissions
kubectl auth can-i create pods --as=system:serviceaccount:security-lab:developer-sa -n security-lab
kubectl auth can-i delete pods --as=system:serviceaccount:security-lab:developer-sa -n security-lab
```

### **Lab 2: Pod Security Standards**
```bash
# Create Pod Security Policy
cat > pod-security-policy.yaml << 'YAML'
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted-psp
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
YAML

kubectl apply -f pod-security-policy.yaml
```

### **Lab 3: Network Policies**
```bash
# Create network policy for microsegmentation
cat > network-policy.yaml << 'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: banking-network-policy
  namespace: security-lab
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: database
    ports:
    - protocol: TCP
      port: 5432
YAML

kubectl apply -f network-policy.yaml
```

## 🏢 **Real-World Use Case: Banking Security Implementation**

### **Scenario: BFSI Security Compliance**
A bank implements comprehensive Kubernetes security for PCI DSS compliance:

```yaml
# Banking security configuration
apiVersion: v1
kind: Namespace
metadata:
  name: banking-secure
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  namespace: banking-secure
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: payment-app
        image: banking/payment-service:v2.1-secure
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

**Benefits Achieved:**
- **PCI DSS Compliance**: Automated security policy enforcement
- **Zero Trust**: Network microsegmentation
- **Audit Trail**: Complete RBAC audit logging
- **Vulnerability Management**: Automated image scanning

## 👨‍💻 **About the Author**
**Varun Kumar Manik** - Kubernetes Expert & AWS Ambassador

*Next: [Session 13 - CI/CD Integration & GitOps](../session-13-k8s-cicd-gitops/)*

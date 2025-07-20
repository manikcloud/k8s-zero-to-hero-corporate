# Troubleshooting Guide: Sidecar Pattern & Istio

## 🔧 **Common Issues and Solutions**

### Issue 1: Sidecar Not Injected

**Symptoms:**
- Pod shows 1/1 containers instead of 2/2
- No istio-proxy container in the pod

**Diagnosis:**
```bash
kubectl get namespace default --show-labels
kubectl describe pod <pod-name>
```

**Solutions:**
1. **Check namespace label:**
   ```bash
   kubectl label namespace default istio-injection=enabled
   ```

2. **Manual injection:**
   ```bash
   istioctl kube-inject -f deployment.yaml | kubectl apply -f -
   ```

3. **Restart deployment:**
   ```bash
   kubectl rollout restart deployment/<deployment-name>
   ```

---

### Issue 2: Application Not Accessible

**Symptoms:**
- Connection refused or timeout errors
- 503 Service Unavailable

**Diagnosis:**
```bash
kubectl get gateway,virtualservice
kubectl get pods -l app=<app-name>
istioctl proxy-status
```

**Solutions:**
1. **Check Gateway configuration:**
   ```bash
   kubectl describe gateway <gateway-name>
   ```

2. **Verify VirtualService:**
   ```bash
   kubectl describe virtualservice <vs-name>
   ```

3. **Check Ingress Gateway:**
   ```bash
   kubectl get svc -n istio-system istio-ingressgateway
   ```

---

### Issue 3: mTLS Connection Issues

**Symptoms:**
- TLS handshake failures
- Connection reset by peer

**Diagnosis:**
```bash
istioctl authn tls-check <pod-name>.<namespace>
kubectl get peerauthentication
```

**Solutions:**
1. **Check PeerAuthentication policy:**
   ```bash
   kubectl get peerauthentication -o yaml
   ```

2. **Verify certificates:**
   ```bash
   istioctl proxy-config secret <pod-name>
   ```

3. **Check Envoy logs:**
   ```bash
   kubectl logs <pod-name> -c istio-proxy
   ```

---

### Issue 4: High Latency

**Symptoms:**
- Slow response times
- Timeouts

**Diagnosis:**
```bash
kubectl port-forward <pod-name> 15000:15000
curl http://localhost:15000/stats | grep -E "(response_time|latency)"
```

**Solutions:**
1. **Check resource limits:**
   ```yaml
   resources:
     limits:
       cpu: 500m
       memory: 512Mi
   ```

2. **Optimize connection pool:**
   ```yaml
   trafficPolicy:
     connectionPool:
       tcp:
         maxConnections: 100
       http:
         http1MaxPendingRequests: 100
   ```

3. **Review circuit breaker settings:**
   ```yaml
   circuitBreaker:
     consecutiveErrors: 5
     interval: 30s
   ```

---

### Issue 5: Memory/CPU Issues

**Symptoms:**
- Pod OOMKilled
- High CPU usage
- Slow performance

**Diagnosis:**
```bash
kubectl top pods
kubectl describe pod <pod-name>
kubectl logs <pod-name> -c istio-proxy --previous
```

**Solutions:**
1. **Increase resource limits:**
   ```yaml
   resources:
     requests:
       memory: "128Mi"
       cpu: "100m"
     limits:
       memory: "256Mi"
       cpu: "200m"
   ```

2. **Optimize Envoy configuration:**
   ```yaml
   metadata:
     annotations:
       sidecar.istio.io/proxyCPU: "100m"
       sidecar.istio.io/proxyMemory: "128Mi"
   ```

---

## 🔍 **Diagnostic Commands**

### General Health Check
```bash
# Check Istio installation
istioctl version
istioctl verify-install

# Check proxy status
istioctl proxy-status

# Analyze configuration
istioctl analyze
```

### Pod-Level Diagnostics
```bash
# Get pod details
kubectl describe pod <pod-name>

# Check container logs
kubectl logs <pod-name> -c <container-name>

# Execute into sidecar
kubectl exec -it <pod-name> -c istio-proxy -- /bin/bash
```

### Network Diagnostics
```bash
# Check Envoy configuration
istioctl proxy-config cluster <pod-name>
istioctl proxy-config listener <pod-name>
istioctl proxy-config route <pod-name>

# Check endpoints
istioctl proxy-config endpoint <pod-name>
```

### Security Diagnostics
```bash
# Check TLS configuration
istioctl authn tls-check <pod-name>.<namespace>

# Check certificates
istioctl proxy-config secret <pod-name>

# Check authorization policies
kubectl get authorizationpolicy
```

---

## 📊 **Monitoring and Observability**

### Key Metrics to Monitor
```bash
# Envoy stats
curl http://localhost:15000/stats

# Important metrics:
# - cluster.outbound|80||service.namespace.svc.cluster.local.upstream_rq_200
# - cluster.outbound|80||service.namespace.svc.cluster.local.upstream_rq_5xx
# - http.inbound_0.0.0.0_80.downstream_rq_time
```

### Distributed Tracing
```bash
# Enable tracing
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio
  namespace: istio-system
data:
  mesh: |
    defaultConfig:
      tracing:
        sampling: 100.0
EOF
```

### Access Logs
```bash
# Enable access logs
istioctl install --set meshConfig.accessLogFile=/dev/stdout
```

---

## 🚨 **Emergency Procedures**

### Disable Sidecar Injection
```bash
# For specific deployment
kubectl patch deployment <deployment-name> -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/inject":"false"}}}}}'

# For namespace
kubectl label namespace <namespace> istio-injection-
```

### Bypass Service Mesh
```bash
# Create service without mesh
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: app-direct
  annotations:
    service.istio.io/canonical-name: app
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
EOF
```

### Emergency Rollback
```bash
# Rollback deployment
kubectl rollout undo deployment/<deployment-name>

# Check rollout status
kubectl rollout status deployment/<deployment-name>
```

---

## 📋 **Best Practices for Troubleshooting**

1. **Always check logs first:**
   ```bash
   kubectl logs <pod-name> -c istio-proxy --tail=100
   ```

2. **Use istioctl analyze:**
   ```bash
   istioctl analyze --all-namespaces
   ```

3. **Check resource usage:**
   ```bash
   kubectl top pods
   kubectl describe node
   ```

4. **Verify configuration:**
   ```bash
   kubectl get gateway,virtualservice,destinationrule -o yaml
   ```

5. **Test connectivity:**
   ```bash
   kubectl exec -it <pod-name> -- curl -v http://service-name/
   ```

---

## 🔗 **Useful Resources**

- [Istio Troubleshooting Guide](https://istio.io/latest/docs/ops/common-problems/)
- [Envoy Documentation](https://www.envoyproxy.io/docs/)
- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug-application-cluster/)
- [Service Mesh Patterns](https://www.oreilly.com/library/view/istio-up-and/9781492043775/)

# Hands-on Lab: Sidecar Pattern with Istio

## 🎯 **Lab Objectives**

By completing this lab, you will:
- Deploy an application with Istio sidecar injection
- Understand how traffic flows through the sidecar proxy
- Configure traffic management policies
- Implement security policies with mTLS
- Monitor and observe sidecar behavior

---

## 🛠 **Prerequisites**

- Kubernetes cluster (minikube, kind, or cloud cluster)
- kubectl configured and working
- Basic understanding of Kubernetes concepts

---

## 📋 **Lab Steps**

### Step 1: Environment Setup

1. **Verify Kubernetes cluster access:**
   ```bash
   kubectl cluster-info
   kubectl get nodes
   ```

2. **Install Istio (if not already installed):**
   ```bash
   curl -L https://istio.io/downloadIstio | sh -
   cd istio-*
   export PATH=$PWD/bin:$PATH
   istioctl version
   ```

3. **Install Istio in the cluster:**
   ```bash
   istioctl install --set values.defaultRevision=default -y
   kubectl get pods -n istio-system
   ```

### Step 2: Enable Sidecar Injection

1. **Label the namespace for automatic sidecar injection:**
   ```bash
   kubectl label namespace default istio-injection=enabled
   kubectl get namespace default --show-labels
   ```

2. **Verify the label is applied:**
   ```bash
   kubectl describe namespace default
   ```

### Step 3: Deploy the Application

1. **Navigate to the demo directory:**
   ```bash
   cd demo-manifests/
   ```

2. **Deploy the application:**
   ```bash
   ./deploy.sh
   ```

3. **Verify the deployment:**
   ```bash
   kubectl get pods -l app=httpd
   # Should show 2/2 containers (app + sidecar)
   ```

### Step 4: Examine the Sidecar

1. **Describe the pod to see both containers:**
   ```bash
   POD_NAME=$(kubectl get pods -l app=httpd -o jsonpath='{.items[0].metadata.name}')
   kubectl describe pod $POD_NAME
   ```

2. **Check the containers in the pod:**
   ```bash
   kubectl get pod $POD_NAME -o jsonpath='{.spec.containers[*].name}'
   # Should show: httpd istio-proxy
   ```

3. **View the Envoy configuration:**
   ```bash
   kubectl port-forward $POD_NAME 15000:15000 &
   curl http://localhost:15000/config_dump | jq .
   ```

### Step 5: Test Traffic Flow

1. **Get the ingress gateway URL:**
   ```bash
   export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
   export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
   ```

2. **If LoadBalancer is not available, use port-forward:**
   ```bash
   kubectl port-forward -n istio-system service/istio-ingressgateway 8080:80 &
   export GATEWAY_URL=localhost:8080
   ```

3. **Test the application:**
   ```bash
   curl -v http://$GATEWAY_URL/
   ```

4. **Generate traffic for testing:**
   ```bash
   for i in {1..10}; do
     curl -s http://$GATEWAY_URL/ > /dev/null
     echo "Request $i completed"
     sleep 1
   done
   ```

### Step 6: Explore Observability

1. **Open Kiali dashboard:**
   ```bash
   istioctl dashboard kiali &
   # Visit http://localhost:20001
   ```

2. **Open Grafana dashboard:**
   ```bash
   istioctl dashboard grafana &
   # Visit http://localhost:3000
   ```

3. **Open Jaeger tracing:**
   ```bash
   istioctl dashboard jaeger &
   # Visit http://localhost:16686
   ```

4. **View Envoy access logs:**
   ```bash
   kubectl logs $POD_NAME -c istio-proxy
   ```

---

## 🔍 **Lab Verification Checklist**

- [ ] Pod shows 2/2 containers running
- [ ] Envoy admin interface accessible on port 15000
- [ ] Application accessible through Istio gateway
- [ ] mTLS enabled and working
- [ ] Traffic policies applied and functional
- [ ] Observability dashboards showing data

---

## 🧹 **Cleanup**

When you're done with the lab:

```bash
./cleanup.sh
```

---

## 🎓 **Lab Summary**

You have successfully:
- ✅ Deployed an application with Istio sidecar
- ✅ Configured traffic management policies
- ✅ Implemented security with mTLS
- ✅ Explored observability features

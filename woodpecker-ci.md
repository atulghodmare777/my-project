# Woodpecker Deployment with Bitbucket

## Bitbucket OAuth Configuration
1. Go to **Workspace settings** in Bitbucket.  
2. Click on **OAuth consumers** → **Add consumer**.  
3. Provide the **Callback URL**:  
   ```
   https://35-244-2-22.nip.io/authorize
   ```
   > **Note:** No need to add the URL elsewhere.
4. Provide the following permissions:
   - **Account**: Email, Read  
   - **Workspace membership**: Read  
   - **Projects**: Read  
   - **Repositories**: Read  
   - **Pull requests**: Read  
   - **Webhooks**: Read + Write  

5. Save. Once saved, hover over the name to get the **Key** and **Secret**.  

---

## Create Agent Secret
Generate the agent secret:
```bash
openssl rand -hex 32
```

Create Kubernetes secret:
```bash
kubectl -n woodpecker-new create secret generic woodpecker-secrets \
  --from-literal=WOODPECKER_BITBUCKET=true \
  --from-literal=WOODPECKER_BITBUCKET_CLIENT='Lpcgt6kKXkBvVVwVm9' \
  --from-literal=WOODPECKER_BITBUCKET_SECRET='ymqxnsnufPf8gwkeMza9h7qGYzWH4hhq' \
  --from-literal=WOODPECKER_AGENT_SECRET='b823c06dc553b0bc09e808adfc6c3a91' \
  --from-literal=WOODPECKER_HOST='https://35-244-2-22.nip.io' \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## Create `values.yaml`
```yaml
server:
  enabled: true
  extraSecretNamesForEnvFrom:
    - woodpecker-secrets
  env:
    WOODPECKER_OPEN: "true"

agent:
  enabled: true
  extraSecretNamesForEnvFrom:
    - woodpecker-secrets

  persistence:
    enabled: true
    size: 1Gi
    storageClass: "standard-rwo"
    accessModes:
      - ReadWriteOnce

  env:
    WOODPECKER_SERVER: "woodpecker-server:9000"
    WOODPECKER_BACKEND: "kubernetes"
    WOODPECKER_BACKEND_K8S_STORAGE_CLASS: "standard-rwo"
    WOODPECKER_BACKEND_K8S_VOLUME_SIZE: "1G"
    WOODPECKER_BACKEND_K8S_STORAGE_RWX: "false"
```

---

## Deploy Woodpecker
```bash
helm install woodpecker oci://ghcr.io/woodpecker-ci/helm/woodpecker \
  -n woodpecker \
  --version 3.3.0 \
  -f values.yaml
```

---

## Modify StatefulSet
Edit the StatefulSet:
```bash
kubectl -n woodpecker-new edit statefulset woodpecker-new-server
```

Add:
```yaml
- name: WOODPECKER_HOST
  value: "https://35-244-2-22.nip.io"
```

---

## Configure Ingress and Certificates

### 1. Check Ingress Controller
```bash
kubectl get pods -A | grep nginx
```

### 2. Install Cert-Manager
Check if cert-manager is installed:
```bash
kubectl get pods -n cert-manager
```

If not, install:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml
```

### 3. Create Issuer
Create `issuer.yaml`:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http
spec:
  acme:
    server: https://acme-v2.api.letsencrypt.org/directory
    email: atul.ghodmare@nviz.com
    privateKeySecretRef:
      name: letsencrypt-http
    solvers:
    - http01:
        ingress:
          class: nginx
```

Apply it:
```bash
kubectl apply -f issuer.yaml
```

### 4. Create Ingress
Create `ingress.yaml` (update hosts to new LoadBalancer IP):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: woodpecker-ingress
  namespace: woodpecker-new
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-http"
spec:
  tls:
  - hosts:
    - 34-93-202-123.nip.io  # load balancer ip
    secretName: woodpecker-tls
  rules:
  - host: 34-93-202-123.nip.io # load balancer ip
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: woodpecker-new-server
            port:
              number: 80
```

Apply it:
```bash
kubectl apply -f ingress.yaml
```

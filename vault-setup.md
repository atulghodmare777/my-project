helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault

Deploy Vault in Production Mode

Create a vault-values.yaml file:
server:
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      setNodeId: true
      config: |
        ui = true

        listener "tcp" {
          tls_disable = 1
          address = "[::]:8200"
          cluster_address = "[::]:8201"
        }

        storage "raft" {
          path = "/vault/data"

          retry_join {
            leader_api_addr = "http://vault-0.vault-internal:8200"
          }
          retry_join {
            leader_api_addr = "http://vault-1.vault-internal:8200"
          }
          retry_join {
            leader_api_addr = "http://vault-2.vault-internal:8200"
          }
        }

        service_registration "kubernetes" {}

  dataStorage:
    enabled: true
    size: 1Gi
    storageClass: "standard-rwo"  # Changed from "default"

  standalone:
    enabled: false

  auditStorage:
    enabled: true
    size: 1Gi
    storageClass: "standard-rwo"  # Keep this consistent

injector:
  enabled: true

helm install vault hashicorp/vault -n vault -f vault-values.yaml

kubectl exec -n vault vault-0 -- vault operator init -key-shares=5 -key-threshold=3

save the keys which we will receive after above command

Unseal vault-0
Use any 3 of the 5 unseal keys you received:

kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY_1>
kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY_2>
kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY_3>

After the 3rd unseal command, you should see Sealed: false in the output.

 Unseal vault-1
 kubectl exec -n vault vault-1 -- vault operator unseal <UNSEAL_KEY_1>
kubectl exec -n vault vault-1 -- vault operator unseal <UNSEAL_KEY_2>
kubectl exec -n vault vault-1 -- vault operator unseal <UNSEAL_KEY_3>

 Unseal vault-2
 kubectl exec -n vault vault-2 -- vault operator unseal <UNSEAL_KEY_1>
kubectl exec -n vault vault-2 -- vault operator unseal <UNSEAL_KEY_2>
kubectl exec -n vault vault-2 -- vault operator unseal <UNSEAL_KEY_3>

check the pods
k get po -n vault

Verify Vault Status
kubectl exec -n vault vault-0 -- vault status
You should see:

Sealed: false
Cluster Mode: active or standby

Login to Vault
kubectl exec -n vault vault-0 -- vault login <ROOT_TOKEN>

Check Raft Cluster Status
kubectl exec -n vault vault-0 -- vault operator raft list-peers
You should see all 3 nodes listed.

[command to upgrade if required: helm upgrade vault hashicorp/vault -n vault -f vault-values.yaml]

# convert the cluster ip to LoadBalancer for vault service
Then access the ui using following url: http://34.180.48.111:8200/ui

# To check the status we can use following command:
curl http://34.180.48.111:8200/v1/sys/health

Note: If want to use ingress then use following file:
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: vault
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: vault.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: vault-ui
            port:
              number: 8200
  tls:
  - hosts:
    - vault.yourdomain.com
    secretName: vault-tls  # Requires a TLS secret (use cert-manager or upload manually)


#  Enable Username/Password Authentication
# Enable userpass auth method
kubectl exec -n vault vault-0 -- vault auth enable userpass

# Verify it's enabled
kubectl exec -n vault vault-0 -- vault auth list

#Create Policies (RBAC)
Admin Policy (Full access):
vi admin-policy.hcl
# Full access to all secrets
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "kv/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage policies
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage auth methods
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage users
path "auth/userpass/users/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

kubectl exec -i -n vault vault-0 -- vault policy write admin-policy - < admin-policy.hcl

#Developer Policy (Read/Write secrets):
vi developer-policy.hcl
# Read and write access to dev secrets
path "secret/data/dev/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "secret/metadata/dev/*" {
  capabilities = ["list", "read"]
}

# Read-only access to prod secrets
path "secret/data/prod/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/prod/*" {
  capabilities = ["list", "read"]
}

kubectl exec -i -n vault vault-0 -- vault policy write dev-policy - < developer-policy.hcl

#App Policy (Read-only for applications):
vi app-policy.hcl
path "secret/data/apps/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/apps/*" {
  capabilities = ["list", "read"]
}

kubectl exec -i -n vault vault-0 -- vault policy write app-policy - < app-policy.hcl

# Create Users with Roles
# Create admin user
kubectl exec -n vault vault-0 -- vault write auth/userpass/users/admin \
    password="AdminPass123!" \
    policies="admin-policy"

# Create developer user
kubectl exec -n vault vault-0 -- vault write auth/userpass/users/atul-dev \
    password="DevPass123!" \
    policies="dev-policy"

# Create another developer
kubectl exec -n vault vault-0 -- vault write auth/userpass/users/jane-dev \
    password="DevPass456!" \
    policies="dev-policy"

# Create application service account
kubectl exec -n vault vault-0 -- vault write auth/userpass/users/app-reader \
    password="AppPass789!" \
    policies="app-policy"

# Now we can login using the username and password as configured above

# we can login using CLI as well
# Login as developer
kubectl exec -n vault vault-0 -- vault login -method=userpass \
    username=john-dev \
    password=DevPass123!

# Check current token info
kubectl exec -n vault vault-0 -- vault token lookup

# List accessible paths (should only see dev/* paths)
kubectl exec -n vault vault-0 -- vault list secret/metadata/

# Enable and Configure KV Secrets Engine
Enable KV v2 Secrets Engine
# Login as root again
kubectl exec -n vault vault-0 -- vault login <YOUR_ROOT_TOKEN>

# Enable KV v2 at path "secret"
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2

# Verify
kubectl exec -n vault vault-0 -- vault secrets list

#  Create Test Secrets
$ Development Secrets:
# Database credentials
kubectl exec -n vault vault-0 -- vault kv put secret/dev/database \
    username="dev_user" \
    password="dev_password_123" \
    host="dev-db.example.com" \
    port="5432"

# API Keys
kubectl exec -n vault vault-0 -- vault kv put secret/dev/api-keys \
    stripe_key="sk_test_123456" \
    sendgrid_key="SG.dev_key_789" \
    github_token="ghp_dev_token_abc"

# Application Config
kubectl exec -n vault vault-0 -- vault kv put secret/dev/app-config \
    app_name="myapp-dev" \
    environment="development" \
    debug_mode="true" \
    log_level="debug"

$ Production Secrets:
# Production Database
kubectl exec -n vault vault-0 -- vault kv put secret/prod/database \
    username="prod_user" \
    password="SuperSecureProdPass123!" \
    host="prod-db.example.com" \
    port="5432" \
    ssl_mode="require"

# Production API Keys
kubectl exec -n vault vault-0 -- vault kv put secret/prod/api-keys \
    stripe_key="sk_live_987654" \
    sendgrid_key="SG.prod_key_456" \
    github_token="ghp_prod_token_xyz"

$ Application Secrets:
# App-specific secrets
kubectl exec -n vault vault-0 -- vault kv put secret/apps/webapp \
    db_connection="postgresql://user:pass@host:5432/db" \
    redis_url="redis://redis:6379/0" \
    jwt_secret="my-super-secret-jwt-key"

kubectl exec -n vault vault-0 -- vault kv put secret/apps/api-service \
    service_account_key='{"type":"service_account","project_id":"my-project"}' \
    oauth_client_id="123456789.apps.googleusercontent.com" \
    oauth_client_secret="client_secret_abc123"
 
# Test Secret Access with Different Users
# Login as developer
kubectl exec -n vault vault-0 -- vault login -method=userpass \
    username=john-dev \
    password=DevPass123!

# Should work - read dev secrets
kubectl exec -n vault vault-0 -- vault kv get secret/dev/database

# Should work - write to dev secrets
kubectl exec -n vault vault-0 -- vault kv put secret/dev/test \
    key1="value1" \
    key2="value2"

# Should work - read prod secrets (read-only)
kubectl exec -n vault vault-0 -- vault kv get secret/prod/database

# Should FAIL - write to prod secrets
kubectl exec -n vault vault-0 -- vault kv put secret/prod/test \
    key="value"
# Expected: permission denied

# Should FAIL - read app secrets
kubectl exec -n vault vault-0 -- vault kv get secret/apps/webapp
# Expected: permission denied

#  Kubernetes Integration - Pod Access to Vault
Enable Kubernetes Authentication
# Login as root
kubectl exec -n vault vault-0 -- vault login <YOUR_ROOT_TOKEN>

# Enable Kubernetes auth
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

# Configure Kubernetes auth to talk to K8s API
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443"

# Create Kubernetes Auth Role
# Create role for pods in 'default' namespace
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/webapp-role \
    bound_service_account_names=webapp-sa \
    bound_service_account_namespaces=default \
    policies=app-policy \
    ttl=24h

# Create Test Application Namespace and ServiceAccount
# Create ServiceAccount
kubectl create serviceaccount webapp-sa -n default

# Verify
kubectl get sa webapp-sa -n default

# Deploy Test Application that Reads from Vault
Create file test-app.yaml:
apiVersion: v1
kind: Pod
metadata:
  name: vault-test-app
  namespace: default
  labels:
    app: vault-test
spec:
  serviceAccountName: webapp-sa
  containers:
  - name: app
    image: ubuntu:22.04
    command: 
      - sleep
      - "3600"
    env:
    - name: VAULT_ADDR
      value: "http://vault.vault.svc.cluster.local:8200"

kubectl apply -f test-app.yaml

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/vault-test-app -n default --timeout=60s

# Test Vault Access from Pod
# Exec into the pod
kubectl exec -it vault-test-app -n default -- bash

# Inside the pod, install curl and jq
apt-get update && apt-get install -y curl jq

# Get Kubernetes service account token
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Login to Vault using Kubernetes auth
VAULT_TOKEN=$(curl -s --request POST \
    --data '{"jwt": "'"$KUBE_TOKEN"'", "role": "webapp-role"}' \
    http://vault.vault.svc.cluster.local:8200/v1/auth/kubernetes/login | jq -r '.auth.client_token')

echo "Vault Token: $VAULT_TOKEN"

# Read secret from Vault
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    http://vault.vault.svc.cluster.local:8200/v1/secret/data/apps/webapp | jq

# Should see the webapp secrets!

# Vault Agent Injector (Sidecar Pattern)
Deploy App with Vault Injector Annotations
Create app-with-vault-injector.yaml:

apiVersion: v1
kind: Pod
metadata:
  name: webapp-with-secrets
  namespace: default
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "webapp-role"
    vault.hashicorp.com/agent-inject-secret-database: "secret/data/apps/webapp"
    vault.hashicorp.com/agent-inject-template-database: |
      {{- with secret "secret/data/apps/webapp" -}}
      export DB_CONNECTION="{{ .Data.data.db_connection }}"
      export REDIS_URL="{{ .Data.data.redis_url }}"
      export JWT_SECRET="{{ .Data.data.jwt_secret }}"
      {{- end }}
spec:
  serviceAccountName: webapp-sa
  containers:
  - name: app
    image: nginx:latest
    ports:
    - containerPort: 80
   
kubectl apply -f app-with-vault-injector.yaml

# Check pods - should see 2 containers (app + vault-agent)
kubectl get pod webapp-with-secrets -n default

# Check the injected secrets
kubectl exec webapp-with-secrets -n default -c app -- cat /vault/secrets/database

#  Store Kubernetes Secrets in Vault
 Migrate Existing K8s Secrets to Vault
 # Create a traditional K8s secret first
kubectl create secret generic app-secret \
    --from-literal=api-key=my-api-key-123 \
    --from-literal=db-password=secret-password \
    -n default

# Extract and store in Vault
kubectl get secret app-secret -n default -o json | \
kubectl exec -i vault-0 -n vault -- vault kv put secret/k8s/default/app-secret \
    api-key="my-api-key-123" \
    db-password="secret-password"

# Verify
kubectl exec -n vault vault-0 -- vault kv get secret/k8s/default/app-secret

# Delete the K8s secret (now managed by Vault)
kubectl delete secret app-secret -n default

# Create External Secrets Operator Integration (Advanced)
Install External Secrets Operator:
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
   external-secrets/external-secrets \
    -n external-secrets-system \
    --create-namespace

Create SecretStore for Vault:
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: default
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "webapp-role"
          serviceAccountRef:
            name: "webapp-sa"


Create ExternalSecret:
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: webapp-secrets
  namespace: default
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: webapp-k8s-secret
    creationPolicy: Owner
  data:
  - secretKey: db_connection
    remoteRef:
      key: apps/webapp
      property: db_connection
  - secretKey: redis_url
    remoteRef:
      key: apps/webapp
      property: redis_url
  - secretKey: jwt_secret
    remoteRef:
      key: apps/webapp
      property: jwt_secret


kubectl apply -f secretstore.yaml
kubectl apply -f externalsecret.yaml

# Verify K8s secret was created from Vault
kubectl get secret webapp-k8s-secret -n default
kubectl get secret webapp-k8s-secret -n default -o yaml

# Advanced Testing Scenarios

Secret Rotation Test
# Update a secret in Vault
kubectl exec -n vault vault-0 -- vault kv put secret/apps/webapp \
    db_connection="postgresql://newuser:newpass@host:5432/db" \
    redis_url="redis://redis:6379/0" \
    jwt_secret="updated-jwt-secret-key"

# For Vault Agent Injector - restart pod to get new secrets
kubectl delete pod webapp-with-secrets -n default
kubectl apply -f app-with-vault-injector.yaml

# For External Secrets - waits for refreshInterval (15s), then auto-updates
kubectl get secret webapp-k8s-secret -n default -o yaml
# Check after 15 seconds - values should update automatically

# Test Secret Versioning
# KV v2 keeps secret versions
kubectl exec -n vault vault-0 -- vault kv get -version=1 secret/apps/webapp
kubectl exec -n vault vault-0 -- vault kv get -version=2 secret/apps/webapp

# Rollback to previous version
kubectl exec -n vault vault-0 -- vault kv rollback -version=1 secret/apps/webapp

# View metadata
kubectl exec -n vault vault-0 -- vault kv metadata get secret/apps/webapp

# Test Audit Logging
# Check audit logs
kubectl logs -n vault vault-0 | grep "secret/data/apps/webapp"

# Or view audit storage if enabled
kubectl exec -n vault vault-0 -- cat /vault/audit/audit.log | tail -20

# Test High Availability
# Check which pod is leader
kubectl exec -n vault vault-0 -- vault status
kubectl exec -n vault vault-1 -- vault status
kubectl exec -n vault vault-2 -- vault status

# Delete the active pod
kubectl delete pod vault-0 -n vault

# Check failover - another pod becomes active
kubectl get pods -n vault -w

# Verify cluster still works
curl http://34.180.48.111:8200/v1/sys/health


# Next Steps for Production

Enable Auto-Unseal with GCP KMS (currently manual unseal)
Enable TLS for Vault API (currently TLS disabled)
Set up Vault Backups (Raft snapshots)
Configure monitoring (Prometheus/Grafana)
Implement secret rotation policies
Set up disaster recovery procedures





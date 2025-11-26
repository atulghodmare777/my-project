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


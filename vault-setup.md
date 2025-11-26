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




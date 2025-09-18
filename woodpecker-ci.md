For bitbucket
GO to workspace setting in the bitbucket
Then click on OAuth consumers
Then add consumer
Then provide the callback url: https://35-244-2-22.nip.io/authorize
No need to add the url in thi
Then provide the permissions as follows:
Account: Email, Read

✔️ Workspace membership: Read

✔️ Projects: Read

✔️ Repositories: Read

✔️ Pull requests: Read

✔️ Webhooks: Read + Write

Then save once save we have to hower over the name we get the key and secret that we have paste in below

kubectl -n woodpecker-new create secret generic woodpecker-secrets \
  --from-literal=WOODPECKER_BITBUCKET=true \
  --from-literal=WOODPECKER_BITBUCKET_CLIENT='Lpcgt6kKXkBvVVwVm9' \
  --from-literal=WOODPECKER_BITBUCKET_SECRET='ymqxnsnufPf8gwkeMza9h7qGYzWH4hhq' \
  --from-literal=WOODPECKER_AGENT_SECRET='b823c06dc553b0bc09e808adfc6c3a91' \
  --from-literal=WOODPECKER_HOST='https://35-244-2-22.nip.io' \
  --dry-run=client -o yaml | kubectl apply -f -

Create values.yaml
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

# Deploy woodpecker
helm install woodpecker oci://ghcr.io/woodpecker-ci/helm/woodpecker \
  -n woodpecker \
  --version 3.3.0 \
  -f values.yaml

# Then modify the sts
kubectl -n woodpecker-new edit statefulset woodpecker-new-server

add the host 
- name: WOODPECKER_HOST
  value: "https://35-244-2-22.nip.io"

# Then using the cert manager create the host "https://35-244-2-22.nip.io" & deploy the ingress follow following steps:

# deploy ingress controller if not deployed already in the cluster we can check by following command:
kubectl get pods -A | grep nginx

# Install cert-manager if not already installed:
k get po -n cert-manager

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml

#Create an Issuer (Let’s Encrypt)
vi issuer.yaml
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

# Deploy an Ingress for Woodpecker
vi ingress.yaml ( after deploy change the hosts to new load balancer ip)

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


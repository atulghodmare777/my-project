First deploy nginx controller and cert manager in the cluster
Then create the values file to deploy the argocd using helm
vi argocd-values.yaml
# argocd-values.yaml
global:
  # optional - used as default host in some templates
  domain: "argocd.35.244.2.22.nip.io"

certificate:
  enabled: true
  domain: "argocd.35.244.2.22.nip.io"
  issuer:
    group: cert-manager.io
    kind: ClusterIssuer
    name: letsencrypt-staging

server:
  # enable main UI ingress
  ingress:
    enabled: true
    controller: generic
    controller: generic
    ingressClassName: "nginx"
    hostname: "argocd.35.244.2.22.nip.io"
    path: /
    pathType: Prefix
    tls: true
    annotations:
      kubernetes.io/ingress.class: "nginx"
      cert-manager.io/cluster-issuer: "letsencrypt-staging"
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"

  ingressGrpc:
    enabled: true
    ingressClassName: "nginx"
    # default hostname will fallback to grpc.<server.hostname> if blank,
    # but we set explicit:
    hostname: "grpc-argocd.35.244.2.22.nip.io"
    path: /
    tls: true
    annotations:
      kubernetes.io/ingress.class: "nginx"
      nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
      cert-manager.io/cluster-issuer: "letsencrypt-staging"
  extraArgs:
    - --insecure

# Aplly the helm command to deploy argocd
helm install argocd argo/argo-cd -n argocd --create-namespace -f argocd-values.yaml

# Acceess the UI
On browser : http://argocd.35.244.2.22.nip.io

#

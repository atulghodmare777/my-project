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

# Create the secret file with ssh 
apiVersion: v1
kind: Secret
metadata:
  name: bitbucket-ssh
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  url: git@bitbucket.org:NvizionSolutions/n7-playground-nginx.git
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACCbcxBjboAhFFNEhe8kPw/uLpkEr1mOq8WxDdzwdvph3QAAAJDCOPxUwjj8
    VAAAAAtzc2gtZWQyNTUxOQAAACCbcxBjboAhFFNEhe8kPw/uLpkEr1mOq8WxDdzwdvph3Q
    AAAEDA4fQFc0IdKiZPD6ByslOsw8XByXcnnH+g8lkWHAaAzptzEGNugCEUU0SF7yQ/D+4u
    mQSvWY6rxbEN3PB2+mHdAAAACnRla3Rvbi1ib3QBAgM=
    -----END OPENSSH PRIVATE KEY-----

  Apply the secret 

  # Install argocd cli
  VERSION=v3.0.11
  curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
argocd version

Login using CLI
get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 
argocd login argocd.35.244.2.22.nip.io --username admin --password 8pXYjTPAoEb-ML8S --insecure
argocd repo list > you can see the repo is automatically added, you can verify through UI as well



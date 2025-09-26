First deploy nginx controller and cert manager in the cluster
Create issuer file which will be used in the ingress configuration as we dont have domain
vi issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: "atul.ghodmare@nviz.com"
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
# create the values file to deploy the argocd using helm
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
  Add public key in the ssh section of butbucket 

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

# Deploy image updater
create values file
vi argocd-image-updater-values.yaml
config:
  argocd:
    serverAddress: "argocd-server.argocd.svc.cluster.local:443"
    insecure: true   # because you passed --insecure in server

rbac:
  enabled: true

serviceAccount:
  create: true
  name: argocd-image-updater

helm upgrade --install argocd-image-updater argo/argocd-image-updater   -n argocd -f argocd-image-updater-values.yaml

Edit cm:  k edit cm argocd-image-updater-config -n argocd 

apiVersion: v1
data:
  artifact-registry.sh: |
    #!/bin/sh
    ACCESS_TOKEN=$(wget --header 'Metadata-Flavor: Google' \
      http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token \
      -q -O - | grep -Eo '"access_token":.*?[^\\]",' | cut -d '"' -f 4)
    echo "oauth2accesstoken:$ACCESS_TOKEN"
  interval: 1m
  kube.events: "false"
  log.level: info
  registries.conf: |
    registries:
    - name: Google Container Registry
      prefix: gcr.io
      api_url: https://gcr.io
      credentials: ext:/app/scripts/artifact-registry.sh
      defaultns: nviz-playground
      insecure: no
      ping: yes
      credsexpire: 15m
      default: true
kind: ConfigMap
metadata:
  annotations:
    meta.helm.sh/release-name: argocd-image-updater
    meta.helm.sh/release-namespace: argocd

Add this in deployment of image updater as well as volume and volume mount
k edit deploy argocd-image-updater -n argocd
volumeMounts:
        - mountPath: /app/config
          name: image-updater-conf
        - mountPath: /app/config/ssh
          name: ssh-known-hosts
        - mountPath: /app/.ssh
          name: ssh-config
        - mountPath: /tmp
          name: tmp
        - mountPath: /app/scripts
          name: artifact-registry
        - mountPath: /app/ssh-keys/id_rsa
          name: ssh-signing-key
          readOnly: true
          subPath: sshPrivateKey
volumes:
      - configMap:
          defaultMode: 493
          items:
          - key: artifact-registry.sh
            path: artifact-registry.sh
          name: argocd-image-updater-config
          optional: true
        name: artifact-registry
      - configMap:
          defaultMode: 420
          items:
          - key: registries.conf
            path: registries.conf
          - key: git.commit-message-template
            path: commit.template
          name: argocd-image-updater-config
          optional: true
        name: image-updater-conf
      - configMap:
          defaultMode: 420
          name: argocd-ssh-known-hosts-cm
          optional: true
        name: ssh-known-hosts
      - configMap:
          defaultMode: 420
          name: argocd-image-updater-ssh-config
          optional: true
        name: ssh-config
      - name: ssh-signing-key
        secret:
          defaultMode: 420
          optional: true
          secretName: ssh-git-creds
      - emptyDir: {}
        name: tmp

  # Create application file
  vi application.yaml
  apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-app
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/image-list: nginx=gcr.io/nviz-playground/nginx-app #(Used nginx in this is the alias which we have used in the next annotations)
    argocd-image-updater.argoproj.io/git-branch: main
    argocd-image-updater.argoproj.io/nginx.update-strategy: newest-build
    argocd-image-updater.argoproj.io/nginx.allow-tags: regexp:^.*
    argocd-image-updater.argoproj.io/write-back-method: git:secret:argocd/bitbucket-ssh # (we had created the ssh key we have directly used here to authenticate when commiting the kustomization)
    argocd-image-updater.argoproj.io/write-back-target: kustomization
spec:
  project: default
  source:
    repoURL: git@bitbucket.org:NvizionSolutions/n7-playground-nginx.git
    targetRevision: main
    path: apps/nginx
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
    syncOptions:
      - ApplyOutOfSyncOnly=true

k apply -f application.yaml ? wait for some time to see the effect

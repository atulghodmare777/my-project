# ArgoCD & Image Updater Setup Guide

This guide walks through deploying ArgoCD with cert-manager integration and configuring the ArgoCD Image Updater for automatic image updates from Google Container Registry.

## Prerequisites

- Kubernetes cluster up and running
- `kubectl` configured to access your cluster
- Helm 3 installed
- NGINX Ingress Controller deployed
- cert-manager deployed

## Table of Contents

1. [SSL Certificate Configuration](#ssl-certificate-configuration)
2. [Deploy ArgoCD](#deploy-argocd)
3. [Access ArgoCD UI](#access-argocd-ui)
4. [Configure Git Repository](#configure-git-repository)
5. [Install ArgoCD CLI](#install-argocd-cli)
6. [Deploy ArgoCD Image Updater](#deploy-argocd-image-updater)
7. [Configure Image Updater for GCR](#configure-image-updater-for-gcr)
8. [Create Application](#create-application)

---

## SSL Certificate Configuration

First, create a ClusterIssuer for Let's Encrypt staging certificates.

### Create ClusterIssuer

```bash
vi issuer.yaml
```

```yaml
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
```

```bash
kubectl apply -f issuer.yaml
```

---

## Deploy ArgoCD

### Create Helm Values File

```bash
vi argocd-values.yaml
```

```yaml
global:
  domain: "argocd.35.244.2.22.nip.io"

certificate:
  enabled: true
  domain: "argocd.35.244.2.22.nip.io"
  issuer:
    group: cert-manager.io
    kind: ClusterIssuer
    name: letsencrypt-staging

server:
  ingress:
    enabled: true
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
    hostname: "grpc-argocd.35.244.2.22.nip.io"
    path: /
    tls: true
    annotations:
      kubernetes.io/ingress.class: "nginx"
      nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
      cert-manager.io/cluster-issuer: "letsencrypt-staging"
      
  extraArgs:
    - --insecure
```

### Install ArgoCD via Helm

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd -n argocd --create-namespace -f argocd-values.yaml
```

---

## Access ArgoCD UI

Once deployed, access ArgoCD in your browser:

```
https://argocd.35.244.2.22.nip.io
```

**Default credentials:**
- Username: `admin`
- Password: Retrieve using the command below

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## Configure Git Repository

### Create SSH Secret for Bitbucket

```bash
vi bitbucket-ssh-secret.yaml
```

```yaml
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
```

```bash
kubectl apply -f bitbucket-ssh-secret.yaml
```

### Add Public Key to Bitbucket

Add the corresponding public SSH key to your Bitbucket repository settings under **SSH Keys**.

---

## Install ArgoCD CLI

```bash
VERSION=v3.0.11
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
argocd version
```

### Login via CLI

```bash
# Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Login to ArgoCD
argocd login argocd.35.244.2.22.nip.io --username admin --password <YOUR_PASSWORD> --insecure

# Verify repository is added
argocd repo list
```

---

## Deploy ArgoCD Image Updater

### Create Values File

```bash
vi argocd-image-updater-values.yaml
```

```yaml
config:
  argocd:
    serverAddress: "argocd-server.argocd.svc.cluster.local:443"
    insecure: true

rbac:
  enabled: true

serviceAccount:
  create: true
  name: argocd-image-updater
```

### Install Image Updater

```bash
helm upgrade --install argocd-image-updater argo/argocd-image-updater \
  -n argocd \
  -f argocd-image-updater-values.yaml
```

---

## Configure Image Updater for GCR

### Edit ConfigMap

```bash
kubectl edit cm argocd-image-updater-config -n argocd
```

Add the following configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
  annotations:
    meta.helm.sh/release-name: argocd-image-updater
    meta.helm.sh/release-namespace: argocd
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
```

### Update Image Updater Deployment

```bash
kubectl edit deploy argocd-image-updater -n argocd
```

Add the following volumes and volume mounts:

**Volume Mounts:**

```yaml
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
```

**Volumes:**

```yaml
volumes:
  - name: artifact-registry
    configMap:
      name: argocd-image-updater-config
      defaultMode: 493
      optional: true
      items:
        - key: artifact-registry.sh
          path: artifact-registry.sh
  - name: image-updater-conf
    configMap:
      name: argocd-image-updater-config
      defaultMode: 420
      optional: true
      items:
        - key: registries.conf
          path: registries.conf
        - key: git.commit-message-template
          path: commit.template
  - name: ssh-known-hosts
    configMap:
      name: argocd-ssh-known-hosts-cm
      defaultMode: 420
      optional: true
  - name: ssh-config
    configMap:
      name: argocd-image-updater-ssh-config
      defaultMode: 420
      optional: true
  - name: ssh-signing-key
    secret:
      secretName: bitbucket-ssh
      defaultMode: 420
      optional: true
  - name: tmp
    emptyDir: {}
```

---

## Create Application

### Create Application Manifest

```bash
vi application.yaml
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-app
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/image-list: nginx=gcr.io/nviz-playground/nginx-app
    argocd-image-updater.argoproj.io/git-branch: main
    argocd-image-updater.argoproj.io/nginx.update-strategy: newest-build
    argocd-image-updater.argoproj.io/nginx.allow-tags: regexp:^.*
    argocd-image-updater.argoproj.io/write-back-method: git:secret:argocd/bitbucket-ssh
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
```

### Apply Application

```bash
kubectl apply -f application.yaml
```

Wait a few moments for the image updater to detect and process new images. Monitor the logs:

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

---

## Verification

Check the application status:

```bash
argocd app get nginx-app
```

View sync status in the ArgoCD UI or via CLI:

```bash
argocd app sync nginx-app
```

---

## Notes

- **nip.io**: This setup uses `nip.io` for DNS resolution without needing a real domain
- **Let's Encrypt Staging**: Using staging environment to avoid rate limits during testing
- **Image Update Strategy**: Configured to use `newest-build` strategy with regex tag matching
- **Write-back Method**: Image updater commits kustomization changes directly to the Git repository

For production environments, switch to Let's Encrypt production server and use a proper domain name.

































Step 1: Create and Configure GCP Service Account
PROJECT_ID=<YOUR_GCP_PROJECT_ID>

# Create a dedicated GCP Service Account for Image Updater
gcloud iam service-accounts create argocd-image-updater \
  --project=${PROJECT_ID} \
  --display-name="Argo CD Image Updater"

# Grant read access to Artifact Registry
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:argocd-image-updater@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"

🔗 Step 2: Bind the GCP SA to Kubernetes via Workload Identity

Allow the Kubernetes ServiceAccount argocd-image-updater (in the argocd namespace) to impersonate the GCP Service Account.

gcloud iam service-accounts add-iam-policy-binding \
  argocd-image-updater@${PROJECT_ID}.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[argocd/argocd-image-updater]"

🧾 Step 3: Annotate the Kubernetes Service Account

Create or patch the Kubernetes ServiceAccount to include the GCP SA annotation.

# file: argocd-image-updater-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-image-updater
  namespace: argocd
  annotations:
    iam.gke.io/gcp-service-account: argocd-image-updater@<YOUR_GCP_PROJECT_ID>.iam.gserviceaccount.com


Apply it:

kubectl apply -f argocd-image-updater-sa.yaml


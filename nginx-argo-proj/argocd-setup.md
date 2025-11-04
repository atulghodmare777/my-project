# ArgoCD & Image Updater Setup Guide

Complete step-by-step guide for deploying ArgoCD with cert-manager integration and configuring ArgoCD Image Updater for automatic image updates from Google Container Registry (GCR).

## 📋 Prerequisites

Before starting, ensure you have:

- ✅ Kubernetes cluster (GKE) up and running
- ✅ `kubectl` configured to access your cluster
- ✅ Helm 3 installed
- ✅ NGINX Ingress Controller deployed
- ✅ cert-manager deployed
- ✅ `gcloud` CLI installed and authenticated
- ✅ Appropriate GCP IAM permissions

---

## 🗂️ Table of Contents

1. [SSL Certificate Configuration](#1-ssl-certificate-configuration)
2. [Deploy ArgoCD](#2-deploy-argocd)
3. [Access ArgoCD UI](#3-access-argocd-ui)
4. [Configure Git Repository](#4-configure-git-repository)
5. [Install ArgoCD CLI](#5-install-argocd-cli)
6. [Deploy ArgoCD Image Updater](#6-deploy-argocd-image-updater)
7. [Configure GCP Workload Identity](#7-configure-gcp-workload-identity)
8. [Configure Image Updater for GCR](#8-configure-image-updater-for-gcr)
9. [Create Application](#9-create-application)
10. [Verification](#10-verification)

---

## 1. SSL Certificate Configuration

### 1.1 Check if ClusterIssuer exists

```bash
kubectl get clusterissuer letsencrypt-staging
```

**If exists:** You'll see the ClusterIssuer details. Skip to step 1.3

**If not exists:** Proceed to step 1.2

### 1.2 Create ClusterIssuer

Create the manifest file:

```bash
cat > issuer.yaml <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: "your-email@example.com"  # Replace with your email
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
```

Apply the manifest:

```bash
kubectl apply -f issuer.yaml
```

### 1.3 Verify ClusterIssuer

```bash
kubectl get clusterissuer letsencrypt-staging
```

Expected output should show `READY: True`

---

## 2. Deploy ArgoCD

### 2.1 Check if ArgoCD namespace exists

```bash
kubectl get namespace argocd
```

**If exists:** Skip to step 2.3

**If not exists:** Proceed to step 2.2

### 2.2 Create ArgoCD namespace

```bash
kubectl create namespace argocd
```

### 2.3 Check if Argo Helm repository is added

```bash
helm repo list | grep argo
```

**If exists:** You'll see `argo` in the list. Skip to step 2.5

**If not exists:** Proceed to step 2.4

### 2.4 Add Argo Helm repository

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

### 2.5 Create ArgoCD Helm values file

Create the values file (replace domain with your actual domain):

```bash
cat > argocd-values.yaml <<EOF
global:
  domain: "stream.n7-sparks.n7net.in"

certificate:
  enabled: true
  domain: "stream.n7-sparks.n7net.in"
  issuer:
    group: cert-manager.io
    kind: ClusterIssuer
    name: letsencrypt-staging

server:
  ingress:
    enabled: true
    controller: generic
    ingressClassName: "nginx"
    hostname: "stream.n7-sparks.n7net.in"
    path: /argocd
    pathType: Prefix
    tls: false
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-staging"
    service:
      port: 80
  extraArgs:
    - --insecure
    - --rootpath
    - /argocd

configs:
  params:
    server.basehref: "/argocd"
    server.rootpath: "/argocd"
    server.insecure: "true"
  cm:
    url: "https://stream.n7-sparks.n7net.in/argocd"
EOF
```

### 2.6 Check if ArgoCD is already installed

```bash
helm list -n argocd | grep argocd
```

**If exists:** ArgoCD is already installed. To upgrade, use:

```bash
helm upgrade argocd argo/argo-cd -n argocd -f argocd-values.yaml
```

**If not exists:** Proceed to step 2.7

### 2.7 Install ArgoCD

```bash
helm install argocd argo/argo-cd -n argocd -f argocd-values.yaml
```

### 2.8 Wait for ArgoCD to be ready

```bash
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### 2.9 Verify ArgoCD installation

```bash
kubectl get pods -n argocd
```

All pods should be in `Running` state.

---

## 3. Access ArgoCD UI

### 3.1 Get ArgoCD admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

**Save this password!**

### 3.2 Access ArgoCD UI

Open your browser and navigate to:

```
https://stream.n7-sparks.n7net.in/argocd
```

**Login credentials:**
- Username: `admin`
- Password: (from step 3.1)

---

## 4. Configure Git Repository

### 4.1 Check if SSH key exists

```bash
ls -la ~/.ssh/argocd_bitbucket
```

**If exists:** Skip to step 4.3 to view the public key

**If not exists:** Proceed to step 4.2

### 4.2 Generate SSH key for ArgoCD

```bash
ssh-keygen -t ed25519 -C "argocd-bitbucket" -f ~/.ssh/argocd_bitbucket -N ""
```

### 4.3 Display public key

```bash
cat ~/.ssh/argocd_bitbucket.pub
```

Copy this public key output.

### 4.4 Add public key to Bitbucket

1. Go to your Bitbucket repository
2. Navigate to **Repository Settings** → **Access Keys**
3. Click **Add key**
4. Paste the public key from step 4.3
5. Give it a label like "ArgoCD Access"
6. Click **Add key**

### 4.5 Check if SSH secret exists in ArgoCD

```bash
kubectl get secret bitbucket-ssh -n argocd
```

**If exists:** Secret already configured. Skip to step 4.7

**If not exists:** Proceed to step 4.6

### 4.6 Create SSH secret for Bitbucket

Create the secret manifest:

```bash
cat > bitbucket-ssh-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: bitbucket-ssh
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  url: git@bitbucket.org:YourOrg/your-repo.git  # Replace with your repo URL
  sshPrivateKey: |
$(cat ~/.ssh/argocd_bitbucket | sed 's/^/    /')
EOF
```
OR If you have currently existing ssh key paste it directly
```bash
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

Apply the secret:

```bash
kubectl apply -f bitbucket-ssh-secret.yaml
```

### 4.7 Verify secret creation

```bash
kubectl get secret bitbucket-ssh -n argocd
```

---

## 5. Install ArgoCD CLI

### 5.1 Check if ArgoCD CLI is installed

```bash
argocd version --client
```

**If installed:** You'll see the version. Skip to step 5.3

**If not installed:** Proceed to step 5.2

### 5.2 Install ArgoCD CLI

```bash
VERSION=v3.1.9 #make it same as argocd version
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
```

Verify installation:

```bash
argocd version --client
```

### 5.3 Login to ArgoCD via CLI

Get the admin password:

```bash
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo $ARGOCD_PASSWORD
```

Login (replace with your domain):

```bash
argocd login stream.n7-sparks.n7net.in/argocd --username admin --password "$ARGOCD_PASSWORD" --insecure
```

### 5.4 Verify repository connection

```bash
argocd repo list
```

You should see your Bitbucket repository listed.

---

## 6. Deploy ArgoCD Image Updater

### 6.1 Check if Image Updater is already installed

```bash
helm list -n argocd | grep argocd-image-updater
```

**If exists:** Image Updater is already installed. Skip to section 7

**If not exists:** Proceed to step 6.2

### 6.2 Create Image Updater values file

```bash
cat > argocd-image-updater-values.yaml <<EOF
config:
  argocd:
    serverAddress: "argocd-server.argocd.svc.cluster.local:443"
    insecure: true

rbac:
  enabled: true

serviceAccount:
  create: true
  name: argocd-image-updater
EOF
```

### 6.3 Install ArgoCD Image Updater

```bash
helm upgrade --install argocd-image-updater argo/argocd-image-updater -n argocd -f argocd-image-updater-values.yaml
```

### 6.4 Verify Image Updater installation

```bash
kubectl get deployment argocd-image-updater -n argocd
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater
```

Pod should be in `Running` state.

---

## 7. Configure GCP Workload Identity

### 7.1 Set environment variables

Update these values according to your GCP project:

```bash
export PROJECT_ID="nviz-playground"
export CLUSTER="n7-playground-cluster"
export LOCATION="asia-south1-c"
export KSA_NS="argocd"
export KSA_NAME="argocd-image-updater"
export GSA_NAME="argocd-image-updater"
export GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
```

### 7.2 Check if Workload Identity is enabled on cluster

```bash
gcloud container clusters describe "$CLUSTER" --location "$LOCATION" --format='value(workloadIdentityConfig.workloadPool)'
```

**If output is empty:** Workload Identity is NOT enabled. Enable it with:

```bash
gcloud container clusters update "$CLUSTER" --location="$LOCATION" --workload-pool="${PROJECT_ID}.svc.id.goog"
```

**If output shows something like `nviz-playground.svc.id.goog`:** Workload Identity is enabled. Continue to next step.

Save the workload pool:

```bash
export WORKLOAD_POOL=$(gcloud container clusters describe "$CLUSTER" --location "$LOCATION" --format='value(workloadIdentityConfig.workloadPool)')
echo "WORKLOAD_POOL = $WORKLOAD_POOL"
```

### 7.3 Check if Google Service Account exists

```bash
gcloud iam service-accounts describe "$GSA_EMAIL" --project "$PROJECT_ID"
```

**If exists:** You'll see the service account details. Skip to step 7.5

**If not exists:** You'll see an error. Proceed to step 7.4

### 7.4 Create Google Service Account

```bash
gcloud iam service-accounts create "$GSA_NAME" \
  --project "$PROJECT_ID" \
  --display-name "ArgoCD Image Updater"
```

### 7.5 Check if Artifact Registry reader role is granted

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --format="table(bindings.role)" \
  --filter="bindings.members:serviceAccount:${GSA_EMAIL} AND bindings.role:roles/artifactregistry.reader"
```

**If output shows `roles/artifactregistry.reader`:** Role already granted. Skip to step 7.7

**If output is empty:** Proceed to step 7.6

### 7.6 Grant Artifact Registry reader role

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="roles/artifactregistry.reader"
```

**Note:** This grants project-wide access to Artifact Registry. For more granular access, you can grant access to specific repositories:

```bash
# For legacy GCR (gcr.io) - Optional
gcloud artifacts repositories add-iam-policy-binding gcr.io \
  --location=us \
  --project="$PROJECT_ID" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="roles/artifactregistry.reader"
```

### 7.7 Check if Workload Identity binding exists

```bash
gcloud iam service-accounts get-iam-policy "$GSA_EMAIL" \
  --project "$PROJECT_ID" \
  --format=json | grep -A 5 "roles/iam.workloadIdentityUser"
```

**If output shows the binding:** Binding already exists. Skip to step 7.9

**If output is empty:** Proceed to step 7.8

### 7.8 Bind Kubernetes SA to Google SA

```bash
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
  --project "$PROJECT_ID" \
  --member "serviceAccount:${WORKLOAD_POOL}[${KSA_NS}/${KSA_NAME}]" \
  --role "roles/iam.workloadIdentityUser"
```

### 7.9 Check if Kubernetes SA has Workload Identity annotation

```bash
kubectl get sa "$KSA_NAME" -n "$KSA_NS" -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}'
```

**If output shows the GSA email:** Annotation already exists. Skip to step 7.11

**If output is empty:** Proceed to step 7.10

### 7.10 Annotate Kubernetes Service Account

```bash
kubectl annotate serviceaccount "${KSA_NAME}" \
  -n "${KSA_NS}" \
  iam.gke.io/gcp-service-account="${GSA_EMAIL}" \
  --overwrite
```

### 7.11 Verify annotation

```bash
kubectl get sa "${KSA_NAME}" -n "${KSA_NS}" -o yaml | grep iam.gke.io/gcp-service-account
```

Expected output:
```
iam.gke.io/gcp-service-account: argocd-image-updater@nviz-playground.iam.gserviceaccount.com
```

### 7.12 Verify Artifact Registry repository exists

```bash
gcloud artifacts repositories describe gcr.io \
  --location=us \
  --project="$PROJECT_ID"
```

**If error:** The legacy GCR repository might not be visible. This is normal if you're using newer Artifact Registry repositories.

---

## 8. Configure Image Updater for GCR

### 8.1 Check if argocd-image-updater-config ConfigMap exists

```bash
kubectl get configmap argocd-image-updater-config -n argocd
```

**If exists:** ConfigMap exists. You may want to back it up before proceeding:

```bash
kubectl get configmap argocd-image-updater-config -n argocd -o yaml > argocd-image-updater-config-backup.yaml
```

Then proceed to step 8.2 to update it.

**If not exists:** Proceed to step 8.2

### 8.2 Create/Update ConfigMap with GCR authentication

Create the ConfigMap (replace `nviz-playground` with your project ID):

```bash
cat > argocd-image-updater-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  artifact-registry.sh: |
    #!/bin/sh
    ACCESS_TOKEN=\$(wget --header 'Metadata-Flavor: Google' \
      http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token \
      -q -O - | grep -Eo '"access_token":.*?[^\\\\]",' | cut -d '"' -f 4)
    echo "oauth2accesstoken:\$ACCESS_TOKEN"
  
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
EOF
```

Apply the ConfigMap:

```bash
kubectl apply -f argocd-image-updater-config.yaml
```

### 8.3 Update Image Updater Deployment with volumes

Create a patch file:

```bash
cat > image-updater-patch.yaml <<EOF
spec:
  template:
    spec:
      containers:
      - name: argocd-image-updater
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
      - name: artifact-registry
        configMap:
          name: argocd-image-updater-config
          defaultMode: 493
          items:
          - key: artifact-registry.sh
            path: artifact-registry.sh
      - name: image-updater-conf
        configMap:
          name: argocd-image-updater-config
          defaultMode: 420
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
      - name: tmp
        emptyDir: {}
EOF
```

Apply the patch:

```bash
kubectl patch deployment argocd-image-updater -n argocd --patch-file image-updater-patch.yaml
```

**Alternative:** If patch command doesn't work, edit manually:

```bash
kubectl edit deployment argocd-image-updater -n argocd
```

And add the volumes and volumeMounts sections from the patch file above.

### 8.4 Restart Image Updater deployment

```bash
kubectl rollout restart deployment/argocd-image-updater -n argocd
```

### 8.5 Wait for rollout to complete

```bash
kubectl rollout status deployment/argocd-image-updater -n argocd
```

### 8.6 Verify Image Updater logs

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=50
```

Look for successful authentication messages to GCR. You should see logs indicating registry configuration is loaded.

---

## 9. Create Application

### 9.1 Ensure your Git repository structure

Your repository should have this structure:

```
your-repo/
├── apps/
│   └── nginx/
│       ├── kustomization.yaml
│       ├── deployment.yaml
│       └── service.yaml
```

**Example `kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
images:
  - name: gcr.io/nviz-playground/nginx-app
    newTag: latest
```

### 9.2 Check if application already exists

```bash
kubectl get application nginx-app -n argocd
```

**If exists:** Application already exists. You may want to delete it first:

```bash
kubectl delete application nginx-app -n argocd
```

Then proceed to step 9.3.

**If not exists:** Proceed to step 9.3

### 9.3 Create Application manifest

Create the application manifest (update with your values):

```bash
cat > application.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-app
  namespace: argocd
  annotations:
    # Image to watch for updates
    argocd-image-updater.argoproj.io/image-list: nginx=gcr.io/nviz-playground/nginx-app
    
    # Git branch to write updates to
    argocd-image-updater.argoproj.io/git-branch: main
    
    # Update strategy: newest-build, latest-version, semver, digest
    argocd-image-updater.argoproj.io/nginx.update-strategy: newest-build
    
    # Allow all tags (or use specific regex)
    argocd-image-updater.argoproj.io/nginx.allow-tags: regexp:^.*
    
    # Write back method using Git
    argocd-image-updater.argoproj.io/write-back-method: git:secret:argocd/bitbucket-ssh
    
    # Write back target (kustomization or helm)
    argocd-image-updater.argoproj.io/write-back-target: kustomization
spec:
  project: default
  source:
    repoURL: git@bitbucket.org:YourOrg/your-repo.git
    targetRevision: main
    path: apps/nginx
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
EOF
```

### 9.4 Apply Application

```bash
kubectl apply -f application.yaml
```

### 9.5 Verify Application creation

```bash
kubectl get application nginx-app -n argocd
```

Check via ArgoCD CLI:

```bash
argocd app get nginx-app
```

---

## 10. Verification

### 10.1 Check Application status via CLI

```bash
argocd app get nginx-app
```

You should see:
- Health Status
- Sync Status
- Last Sync information

### 10.2 Check Application in ArgoCD UI

1. Open ArgoCD UI: `https://stream.n7-sparks.n7net.in/argocd`
2. Login with admin credentials
3. You should see `nginx-app` application
4. Click on it to see the resource tree

### 10.3 Monitor Image Updater logs

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

You should see logs indicating:
- Registry configuration loaded
- Image checks being performed
- Write-back operations (if new images are found)

### 10.4 Force sync application

If the application is not synced:

```bash
argocd app sync nginx-app
```

### 10.5 Check if Image Updater can access GCR

Get a shell in the Image Updater pod:

```bash
kubectl exec -it -n argocd deployment/argocd-image-updater -- sh
```

Inside the pod, test GCR authentication:

```bash
/app/scripts/artifact-registry.sh
```

You should see an access token output like:
```
oauth2accesstoken:ya29.c.abc...xyz
```

Test GCR API access (replace with your project and image):

```bash
TOKEN=$(/app/scripts/artifact-registry.sh | cut -d: -f2)
curl -H "Authorization: Bearer $TOKEN" https://gcr.io/v2/nviz-playground/nginx-app/tags/list
```

You should see a JSON response with image tags.

Exit the pod:

```bash
exit
```

### 10.6 Check deployed resources

Check if the application resources are deployed:

```bash
kubectl get all -n default -l app=nginx-app
```

Replace `app=nginx-app` with appropriate labels from your manifests.

### 10.7 Push a new image to test auto-update

Build and push a new image to test the Image Updater:

```bash
# Example: Build and push new image
docker build -t gcr.io/nviz-playground/nginx-app:v1.0.1 .
docker push gcr.io/nviz-playground/nginx-app:v1.0.1
```

Wait for Image Updater to detect the change (check logs):

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

You should see:
1. Image Updater detecting the new image
2. Updating the kustomization.yaml in Git
3. ArgoCD syncing the new version

---

## 📝 Common Commands Reference

### ArgoCD Commands

```bash
# List all applications
argocd app list

# Get application details
argocd app get nginx-app

# Sync application
argocd app sync nginx-app

# View application history
argocd app history nginx-app

# Rollback application
argocd app rollback nginx-app <revision-number>

# Delete application
argocd app delete nginx-app

# List repositories
argocd repo list

# Add repository
argocd repo add git@bitbucket.org:YourOrg/your-repo.git --ssh-private-key-path ~/.ssh/argocd_bitbucket
```

### Kubernetes Commands

```bash
# View ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# View Image Updater logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f

# Restart Image Updater
kubectl rollout restart deployment/argocd-image-updater -n argocd

# Get all resources in argocd namespace
kubectl get all -n argocd

# Describe Image Updater deployment
kubectl describe deployment argocd-image-updater -n argocd

# Check service account annotation
kubectl get sa argocd-image-updater -n argocd -o yaml
```

### GCP Commands

```bash
# List service accounts
gcloud iam service-accounts list --project="$PROJECT_ID"

# Get service account IAM policy
gcloud iam service-accounts get-iam-policy "$GSA_EMAIL" --project="$PROJECT_ID"

# List GCR images
gcloud artifacts docker images list gcr.io/$PROJECT_ID

# List image tags
gcloud artifacts docker tags list gcr.io/$PROJECT_ID/nginx-app
```

---

## 🔧 Troubleshooting

### Issue 1: Image Updater cannot authenticate to GCR

**Check:**

```bash
# Verify Workload Identity annotation
kubectl get sa argocd-image-updater -n argocd -o yaml | grep iam.gke.io

# Verify IAM binding
gcloud iam service-accounts get-iam-policy "$GSA_EMAIL" --project="$PROJECT_ID"

# Check Image Updater logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=100
```

**Fix:** Re-run steps 7.8 and 7.10, then restart the deployment (step 8.4)

### Issue 2: Image Updater not detecting new images

**Check:**

```bash
# Verify registry configuration
kubectl get cm argocd-image-updater-config -n argocd -o yaml

# Check Image Updater logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

**Fix:** 
- Verify the image exists in GCR
- Check the annotation in application manifest (step 9.3)
- Restart Image Updater (step 8.4)

### Issue 3: Git write-back failing

**Check:**

```bash
# Verify SSH secret
kubectl get secret bitbucket-ssh -n argocd -o yaml

# Test SSH connection from Image Updater pod
kubectl exec -it -n argocd deployment/argocd-image-updater -- sh
ssh -T git@bitbucket.org
```

**Fix:** Ensure the SSH key is added to Bitbucket (step 4.4)

### Issue 4: Application not syncing

**Check:**

```bash
# Check application status
argocd app get nginx-app

# Check ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50
```

**Fix:**

```bash
# Force sync
argocd app sync nginx-app

# If still failing, check repository connection
argocd repo list
```

---

## 🚀 Production Recommendations

Before deploying to production:

1. **Switch to Let's Encrypt Production**
   - Update `issuer.yaml` server to: `https://acme-v02.api.letsencrypt.org/directory`
   - Change ClusterIssuer name to `letsencrypt-prod`

2. **Use proper domain instead of nip.io**
   - Update all domain references in `argocd-values.yaml`

3. **Secure ArgoCD admin password**
   - Change the default admin password
   - Consider setting up SSO/OIDC

4. **Implement RBAC**
   - Configure ArgoCD RBAC policies
   - Create separate service accounts for different teams

5. **Set up monitoring**
   - Configure Prometheus metrics
   - Set up alerts for sync failures

6. **Configure backup**
   - Back up ArgoCD configuration
   - Document disaster recovery procedures

7. **Use specific image tags**
   - Instead of `regexp:^.*`, use specific tag patterns
   - Consider using semantic versioning

8. **Separate environments**
   - Use different namespaces for dev/staging/prod
   - Use different Git branches

---

##



## Backup 
cmd: argocd version
create backup directory
helm get values argocd -n argocd > backup/argocd-values.backup.yaml

helm get values argocd-image-updater -n argocd > backup/argocd-image-updater-values.backup.yaml

argocd admin export -n argocd > backup/argocd-backup-$(date +%F).yaml

## To restore the argocd
helm repo add argo https://argoproj.github.io/argo-helm || true

helm repo update

helm upgrade --install argocd argo/argo-cd -n argocd -f backup/argocd-values.backup.yaml

yq 'del(.items[] | select(.kind=="Secret" and .metadata.name=="argocd-secret").data."admin.password") |
    del(.items[] | select(.kind=="Secret" and .metadata.name=="argocd-secret").data."admin.passwordMtime")' \
  backup/argocd-backup-2025-11-04.yaml > /tmp/argocd-backup-sanitized.yaml

argocd admin import -n argocd /tmp/argocd-backup-sanitized.yaml

kubectl get secret bitbucket-ssh -n argocd

Create/apply if missing

kubectl apply -f backup/bitbucket-ssh-secret.yaml

helm upgrade --install argocd-image-updater argo/argocd-image-updater \
  -n argocd -f backup/argocd-image-updater-values.backup.yaml

patch cm as below

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  artifact-registry.sh: |
    #!/bin/sh
    ACCESS_TOKEN=$(wget --header 'Metadata-Flavor: Google' \
      http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token \
      -q -O - | grep -Eo '"access_token":.*?[^\\]",' | cut -d '"' -f 4)
    echo "oauth2accesstoken:${ACCESS_TOKEN}"

  interval: "1m"
  kube.events: "false"
  log.level: "info"

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
EOF


kubectl patch deployment argocd-image-updater -n argocd --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{
    "name":"artifact-registry",
    "configMap":{
      "name":"argocd-image-updater-config",
      "defaultMode":493,
      "items":[{"key":"artifact-registry.sh","path":"artifact-registry.sh"}]
    }
  }}
]'


kubectl patch deployment argocd-image-updater -n argocd --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{
    "mountPath":"/app/scripts",
    "name":"artifact-registry"
  }}
]'


kubectl rollout restart deployment/argocd-image-updater -n argocd

kubectl get sa argocd-image-updater -n argocd -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}'; echo

If empty, annotate:

export PROJECT_ID="nviz-playground"
export KSA_NS="argocd"
export KSA_NAME="argocd-image-updater"
export GSA_NAME="argocd-image-updater"
export GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

kubectl annotate serviceaccount "${KSA_NAME}" -n "${KSA_NS}" \
  iam.gke.io/gcp-service-account="${GSA_EMAIL}" --overwrite

Check IAM binding:

export CLUSTER="n7-playground-cluster"
export LOCATION="asia-south1-c"
export WORKLOAD_POOL=$(gcloud container clusters describe "$CLUSTER" --location "$LOCATION" --format='value(workloadIdentityConfig.workloadPool)')

gcloud iam service-accounts get-iam-policy "$GSA_EMAIL" --project "$PROJECT_ID" \
  --format="json" | grep -q roles/iam.workloadIdentityUser && echo "binding: OK" || echo "binding: MISSING"

If missing, add:

gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
  --member "serviceAccount:${WORKLOAD_POOL}[${KSA_NS}/${KSA_NAME}]" \
  --role "roles/iam.workloadIdentityUser" \
  --project "$PROJECT_ID"

# CHECK whether kubeip-gcp-sa already has Artifact Registry reader
gcloud projects get-iam-policy nviz-playground \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)" \
  --filter="bindings.members:serviceAccount:kubeip-gcp-sa@nviz-playground.iam.gserviceaccount.com AND bindings.role:roles/artifactregistry.reader"

# If the table is empty, then ADD the role:
gcloud projects add-iam-policy-binding nviz-playground \
  --member="serviceAccount:kubeip-gcp-sa@nviz-playground.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"

Install argocd cli

VERSION=v3.1.9 #make it same as argocd version
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
Verify installation:

argocd version --client

Login argocd using CLI

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

argocd login 35-244-2-22.nip.io \
  --username admin \
  --password 'DtEahe93LIKB7Yip' \
  --insecure \
  --grpc-web
Final checks

# UI/Ingress
kubectl get ing -n argocd

# Apps & sync
argocd app list

argocd app get nginx-app

argocd app sync nginx-app   # if OutOfSync

# Image Updater logs + token script
kubectl logs -n argocd deploy/argocd-image-updater --tail=200

kubectl exec -it -n argocd deploy/argocd-image-updater -- sh -c '/app/scripts/artifact-registry.sh'




# Tekton CI/CD Pipeline Setup Guide

> A comprehensive guide to deploying and configuring Tekton Pipelines on GKE with Bitbucket integration.

---

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Workload Identity Configuration](#workload-identity-configuration)
- [Install Ingress Controller & Cert Manager](#install-ingress-controller--cert-manager)
- [Install Tekton Operator](#install-tekton-operator)
- [Install Tekton CLI](#install-tekton-cli)
- [Bitbucket Authentication Setup](#bitbucket-authentication-setup)
- [Stage 1: Clone Repository and Read Files](#stage-1-clone-repository-and-read-files)
- [Stage 2: Build and Push to Artifact Registry](#stage-2-build-and-push-to-artifact-registry)
- [Stage 3: Automate with Triggers](#stage-3-automate-with-triggers)
- [Create Ingress Configuration](#create-ingress-configuration)
- [Configure Bitbucket Webhook](#configure-bitbucket-webhook)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, ensure you have:

- GKE cluster with appropriate permissions
- `gcloud` CLI installed and configured
- `kubectl` configured to access your cluster
- Bitbucket repository access

---

## Workload Identity Configuration

### 🔍 Issue Encountered

When the pipeline ran with build and push tasks, the push was failing due to permission errors. The pod was not assuming the assigned Service Account (SA) and was using the default SA instead.

### ✅ Solution

Cluster-level Workload Identity (WI) was enabled, but the old nodepool was still running. WI is automatically enabled only for new nodepools, so we manually updated the existing nodepool.

### Steps

**1. Check if Cluster-Level Workload Identity is Enabled**

```bash
gcloud container clusters describe n7-playground-cluster \
    --project=nviz-playground \
    --zone=asia-south1-c \
    --format="value(workloadIdentityConfig.workloadPool)"
```

**2. Enable Workload Identity on Cluster (if not enabled)**

```bash
gcloud container clusters update n7-playground-cluster \
    --zone asia-south1-c \
    --workload-pool=nviz-playground.svc.id.goog
```

**3. Check if Nodepool has Workload Identity Enabled**

```bash
gcloud container node-pools describe swap-memory-pool \
    --cluster=n7-playground-cluster \
    --zone=asia-south1-c \
    --format="yaml(config.workloadMetadataConfig)"
```

**4. Enable Workload Identity on Nodepool**

```bash
gcloud container node-pools update nodepool-name \
    --cluster=cluster-name \
    --zone=asia-south1-c \
    --workload-metadata=GKE_METADATA
```

---

## Install Ingress Controller & Cert Manager

> **Why?** Bitbucket webhooks require a public HTTPS endpoint. We install nginx ingress and cert-manager to expose the Tekton EventListener and Dashboard.

### Install Ingress Controller

```bash
kubectl create ns ingress-nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx
```

### Install Cert Manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.crds.yaml
kubectl create ns cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager -n cert-manager
```

---

## Install Tekton Operator

> **Why?** The Operator installs Pipelines, Triggers, and Dashboard in one go. Profile `all` ensures you get Pipelines (to run CI), Triggers (to respond to webhooks), and Dashboard (to view runs).

**1. Install Tekton Operator**

```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/operator/latest/release.yaml
```

**2. Create Tekton Configuration**

Create `tektonconfig.yaml`:

```yaml
apiVersion: operator.tekton.dev/v1alpha1
kind: TektonConfig
metadata:
  name: config
spec:
  profile: all
  targetNamespace: tekton-pipelines
```

**3. Apply Configuration and Watch Pods**

```bash
kubectl apply -f tektonconfig.yaml
kubectl get pods -n tekton-pipelines --watch
```

---

## Install Tekton CLI

```bash
# Download latest release (Linux AMD64)
curl -LO https://github.com/tektoncd/cli/releases/download/v0.36.0/tkn_0.36.0_Linux_x86_64.tar.gz

# Extract
tar xvzf tkn_0.36.0_Linux_x86_64.tar.gz

# Move binary to PATH
sudo mv tkn /usr/local/bin/

# Verify installation
tkn version
```

---

## Bitbucket Authentication Setup

### Generate SSH Key

```bash
ssh-keygen -t ed25519 -C "tekton-bot" -f ./tekton-ssh-key -N ""
ssh -i ./tekton-ssh-key git@bitbucket.org
ssh-keyscan bitbucket.org > known_hosts
mv ./tekton-ssh-key ~/.ssh/
mv ./tekton-ssh-key.pub ~/.ssh/
chmod 600 ~/.ssh/tekton-ssh-key
chmod 644 ~/.ssh/tekton-ssh-key.pub
```

### Add Public Key to Bitbucket

1. Copy the contents of `~/.ssh/tekton-ssh-key.pub`
2. Go to Bitbucket → **Personal Settings** → **SSH Keys**
3. Add the public key

### Verify Authentication

```bash
ssh -T git@bitbucket.org
```

### Create SSH Config

Create `~/.ssh/config` and add:

```
Host bitbucket.org
  User git
  IdentityFile ~/.ssh/tekton-ssh-key
```

### Create Kubernetes Secret

**1. Encode files to base64:**

```bash
cat ~/.ssh/tekton-ssh-key | base64 -w 0
cat ~/.ssh/known_hosts | base64 -w 0
cat ~/.ssh/config | base64 -w 0
```

**2. Create `bitbucket-secret.yaml`:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: git-credentials
  namespace: test
data:
  tekton-ssh-key: <BASE64_ENCODED_PRIVATE_KEY>
  known_hosts: <BASE64_ENCODED_KNOWN_HOSTS>
  config: <BASE64_ENCODED_CONFIG>
```

**3. Apply the secret:**

```bash
kubectl apply -f bitbucket-secret.yaml
```

---

## Stage 1: Clone Repository and Read Files

This stage demonstrates cloning a private repository and reading files from it.

### Install Git Clone Task

```bash
tkn hub install task git-clone -n test
```

Or use a specific version (recommended - version 0.6):

```bash
kubectl apply -f \
https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.6/git-clone.yaml -n test
```

> ⚠️ **Note:** Use version 0.6 as the latest version may not work as expected.

### Create Show README Task

Create `readme.yaml`:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: show-readme
  namespace: test
spec:
  description: Read and display README file.
  workspaces:
  - name: source
  steps:
  - name: read
    image: alpine:latest
    script: |
      #!/usr/bin/env sh
      cat $(workspaces.source.path)/main_test.go
```

### Create Pipeline

Create `pipeline.yaml`:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: clone-read
  namespace: test
spec:
  description: |
    This pipeline clones a git repo, then echoes the README file to the stout.
  params:
  - name: repo-url
    type: string
    description: The git repo URL to clone from.
  workspaces:
  - name: shared-data
    description: |
      This workspace contains the cloned repo files, so they can be read by the
      next task.
  - name: git-credentials
    description: My ssh credentials
  tasks:
  - name: fetch-source
    taskRef:
      name: git-clone
    workspaces:
    - name: output
      workspace: shared-data
    - name: ssh-directory
      workspace: git-credentials
    params:
    - name: url
      value: $(params.repo-url)
  - name: show-readme
    runAfter: ["fetch-source"]
    taskRef:
      name: show-readme
    workspaces:
    - name: source
      workspace: shared-data
```

### Create PipelineRun

Create `pipelinerun.yaml`:

```yaml
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: clone-read-run-
  namespace: test
spec:
  pipelineRef:
    name: clone-read
  podTemplate:
    securityContext:
      fsGroup: 65532
  workspaces:
  - name: shared-data
    volumeClaimTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 1Gi
  - name: git-credentials
    secret:
      secretName: git-credentials
  params:
  - name: repo-url
    value: git@bitbucket.org:NvizionSolutions/infra-check.git
```

### Execute the Pipeline

```bash
# Apply the show-readme Task
kubectl apply -f readme.yaml

# Apply the Pipeline
kubectl apply -f pipeline.yaml

# Create the PipelineRun
kubectl create -f pipelinerun.yaml
```

Expected output:
```
pipelinerun.tekton.dev/clone-read-run-4kgjr created
```

### Monitor Pipeline Execution

```bash
tkn pipelinerun list -n test
```

✅ **Success!** This demonstrates successful private repository cloning.

---

## Stage 2: Build and Push to Artifact Registry

This stage clones the repository, builds a Docker image, and pushes it to Google Artifact Registry.

### Enable Artifact Registry API

**Check if already enabled:**

```bash
gcloud services list --filter="name:artifactregistry.googleapis.com"
```

**Enable the service:**

```bash
gcloud services enable artifactregistry.googleapis.com
```

### Create Docker Repository

```bash
gcloud artifacts repositories create <repository-name> \
  --repository-format=docker \
  --location=us-central1 \
  --description="Docker repository"
```

### Configure Service Accounts and Workload Identity

**1. Create Kubernetes Service Account:**

```bash
kubectl create serviceaccount tekton-sa -n test
```

**2. Create GCP IAM Service Account:**

```bash
gcloud iam service-accounts create tekton-sa
```

**3. Grant Artifact Registry permissions:**

```bash
gcloud artifacts repositories add-iam-policy-binding zendesk \
  --location asia-south1 \
  --member=serviceAccount:tekton-sa@nviz-playground.iam.gserviceaccount.com \
  --role=roles/artifactregistry.reader

gcloud artifacts repositories add-iam-policy-binding zendesk \
  --location asia-south1 \
  --member=serviceAccount:tekton-sa@nviz-playground.iam.gserviceaccount.com \
  --role=roles/artifactregistry.writer
```

**4. Annotate Kubernetes Service Account:**

```bash
kubectl annotate serviceaccount tekton-sa \
  iam.gke.io/gcp-service-account=tekton-sa@nviz-playground.iam.gserviceaccount.com \
  -n test
```

**5. Bind Workload Identity:**

```bash
gcloud iam service-accounts add-iam-policy-binding \
  tekton-sa@nviz-playground.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:nviz-playground.svc.id.goog[test/tekton-sa]"
```

> 💡 **Note:** This creates two service accounts (IAM and Kubernetes) and links them using Workload Identity, allowing GKE workloads to access Google Cloud services.

### Verify Prerequisites

**Check if git credentials secret exists:**

```bash
kubectl get secret -n test
```

**Check if git-clone task is installed:**

```bash
tkn tasks list -n test
```

If not installed:

```bash
tkn hub install task git-clone -n test
```

### Create Kaniko Build Task

Create `kaniko-build.yaml`:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: kaniko-gke-build
  namespace: test
spec:
  params:
    - name: IMAGE
      type: string
      description: The name of the image to build and push.
    - name: CONTEXT
      type: string
      description: The build context path.
      default: ./
  workspaces:
    - name: source
      description: The workspace with the source code.
  steps:
    - name: build-and-push
      image: gcr.io/kaniko-project/executor:v1.9.0-debug
      securityContext:
        runAsUser: 0
      args:
        - --dockerfile=Dockerfile
        - --context=$(workspaces.source.path)/$(params.CONTEXT)
        - --destination=$(params.IMAGE)
        - --oci-layout-path=/workspace/oci
```

### Create Pipeline

Create `pipeline.yaml`:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: clone-build-push
  namespace: test
spec:
  description: |
    This pipeline clones a git repo, builds a Docker image with Kaniko and
    pushes it to a registry
  params:
  - name: repo-url
    type: string
  - name: image-reference
    type: string
  workspaces:
  - name: shared-data
  - name: git-credentials
    description: My ssh credentials
  tasks:
  - name: fetch-source
    taskRef:
      name: git-clone
    workspaces:
    - name: output
      workspace: shared-data
    - name: ssh-directory
      workspace: git-credentials
    params:
    - name: url
      value: $(params.repo-url)
  - name: build-push
    runAfter: ["fetch-source"]
    taskRef:
      name: kaniko-gke-build
    workspaces:
    - name: source
      workspace: shared-data
    params:
    - name: IMAGE
      value: $(params.image-reference)
```

### Create PipelineRun

Create `pipelinerun.yaml`:

```yaml
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: clone-build-push-run-
  namespace: test
spec:
  serviceAccountName: tekton-sa
  pipelineRef:
    name: clone-build-push
  podTemplate:
    securityContext:
      fsGroup: 65532
      runAsUser: 0
  workspaces:
  - name: shared-data
    volumeClaimTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 1Gi
  - name: git-credentials
    secret:
      secretName: git-credentials
  params:
  - name: repo-url
    value: git@bitbucket.org:NvizionSolutions/n7-playground-nginx.git
  - name: image-reference
    value: asia-south1-docker.pkg.dev/nviz-playground/zendesk/zendesk/myimage:latest
```

### Execute the Pipeline

```bash
kubectl apply -f kaniko-build.yaml
kubectl apply -f pipeline.yaml
kubectl create -f pipelinerun.yaml
```

### Monitor Pipeline Execution

```bash
tkn pipelinerun list -n test
tkn pipelinerun logs <pipelinerun-name> -n test
```

---

## Stage 3: Automate with Triggers

Automate pipeline execution using Tekton Triggers in response to Bitbucket webhook events with **tag commit** ex: v1.0.1

### Prerequisites

Ensure pipeline and tasks are already present in the namespace from Stage 2.

### Install Required Tasks

```bash
tkn hub install task git-clone -n test
tkn task list -n test
```

### Create Kaniko Build Task

Create `kaniko-build.yaml`:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: kaniko-gke-build
  namespace: test
spec:
  params:
    - name: IMAGE
      type: string
      description: The name of the image to build and push.
    - name: CONTEXT
      type: string
      description: The build context path.
      default: ./
  workspaces:
    - name: source
      description: The workspace with the source code.
  steps:
    - name: build-and-push
      image: gcr.io/kaniko-project/executor:v1.9.0-debug
      securityContext:
        runAsUser: 0
      args:
        - --dockerfile=Dockerfile
        - --context=$(workspaces.source.path)/$(params.CONTEXT)
        - --destination=$(params.IMAGE)
        - --oci-layout-path=/workspace/oci
```

### Create Pipeline

Create `pipeline.yaml`:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: clone-build-push
  namespace: test
spec:
  description: |
    This pipeline clones a git repo, builds a Docker image with Kaniko and
    pushes it to a registry
  params:
  - name: repo-url
    type: string
  - name: image-reference
    type: string
  workspaces:
  - name: shared-data
  - name: git-credentials
    description: My ssh credentials
  tasks:
  - name: fetch-source
    taskRef:
      name: git-clone
    workspaces:
    - name: output
      workspace: shared-data
    - name: ssh-directory
      workspace: git-credentials
    params:
    - name: url
      value: $(params.repo-url)
  - name: build-push
    runAfter: ["fetch-source"]
    taskRef:
      name: kaniko-gke-build
    workspaces:
    - name: source
      workspace: shared-data
    params:
    - name: IMAGE
      value: $(params.image-reference)
```

### Configure RBAC

#### Create Role & Rolebinding

Create `tekton-sa-role-rolebinding.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tekton-triggers-role
  namespace: test
rules:
  - apiGroups: ["triggers.tekton.dev"]
    resources: ["triggers", "triggertemplates", "triggerbindings", "eventlisteners", "interceptors"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["tekton.dev"]
    resources: ["pipelineruns", "tasks", "taskruns"]
    verbs: ["get", "list", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tekton-triggers-binding
  namespace: test
subjects:
  - kind: ServiceAccount
    name: tekton-sa
    namespace: test
roleRef:
  kind: Role
  name: tekton-triggers-role
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl apply -f tekton-sa-role-rolebinding.yaml
```

#### Create ClusterRole and ClusterRoleBinding

Create `cluster-role-rolebinding.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-clusterrole
rules:
  - apiGroups: ["triggers.tekton.dev"]
    resources: ["clustertriggerbindings", "clusterinterceptors"]
    verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-clusterrolebinding
subjects:
  - kind: ServiceAccount
    name: tekton-sa
    namespace: test
roleRef:
  kind: ClusterRole
  name: tekton-triggers-clusterrole
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl apply -f cluster-role-rolebinding.yaml
```

### Create Trigger Resources

#### ClusterTriggerBinding

Create `clustertriggerbinding.yaml`:

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: ClusterTriggerBinding
metadata:
  name: bitbucket-push-clusterbinding
spec:
  params:
    - name: repo_full_name
      value: $(body.repository.full_name)
    - name: branch
      value: $(body.push.changes[0].new.name)
    - name: commit_sha
      value: $(body.push.changes[0].new.target.hash)
    - name: tag_name
      value: $(body.push.changes[0].new.name)
    - name: change_type
      value: $(body.push.changes[0].new.type)
```

#### TriggerTemplate

Create `trigger-template.yaml`:

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: bitbucket-push-template
  namespace: test
spec:
  params:
    - name: repo_full_name
    - name: branch
    - name: commit_sha
    - name: tag_name
  resourcetemplates:
    - apiVersion: tekton.dev/v1beta1
      kind: PipelineRun
      metadata:
        generateName: clone-build-push-run-
        namespace: test
      spec:
        serviceAccountName: tekton-sa
        pipelineRef:
          name: clone-build-push
        podTemplate:
          securityContext:
           fsGroup: 65532
           runAsUser: 0
        workspaces:
          - name: shared-data
            volumeClaimTemplate:
              spec:
                accessModes: ["ReadWriteOnce"]
                resources:
                  requests:
                    storage: 1Gi
          - name: git-credentials
            secret:
              secretName: git-credentials
        params:
          - name: repo-url
            value: git@bitbucket.org:$(tt.params.repo_full_name).git
          - name: image-reference
            value: asia-south1-docker.pkg.dev/nviz-playground/zendesk/zendesk/myimage:$(tt.params.tag_name)
```

#### Trigger

Create `trigger.yaml`:

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: Trigger
metadata:
  name: bitbucket-push-trigger
  namespace: test
spec:
  bindings:
    - kind: ClusterTriggerBinding
      ref: bitbucket-push-clusterbinding
  template:
    ref: bitbucket-push-template
  interceptors:
    - ref:
        name: "cel"
      params:
        - name: "filter"
          value: |
            body.push.changes.size() > 0 &&
            body.push.changes[0].new != null &&
            body.push.changes[0].new.type == "tag" &&
            body.push.changes[0].new.name.matches('^v([0-9]+)\\.([0-9]+)\\.([0-9]+)$')
```

#### EventListener

Create `event-listener.yaml`:

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: bitbucket-listener
  namespace: test
spec:
  serviceAccountName: tekton-sa
  triggers:
    - triggerRef: bitbucket-push-trigger
```

### Apply All Trigger Resources

```bash
kubectl apply -f clustertriggerbinding.yaml        
kubectl apply -f trigger-template.yaml
kubectl apply -f trigger.yaml
kubectl apply -f event-listener.yaml
```

### Verify Resources

```bash
kubectl get clustertriggerbindings
kubectl get triggertemplate -n test
kubectl get trigger -n test
kubectl get eventlistener -n test
```

---

## Create Ingress Configuration

Create an Ingress to expose the EventListener publicly for Bitbucket webhooks.

Create `bitbucket-listener-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bitbucket-listener-ingress
  namespace: test
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
    - host: bitbucket-listener.35.244.2.22.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: el-bitbucket-listener
                port:
                  number: 8080
```

**Apply the Ingress:**

```bash
kubectl apply -f bitbucket-listener-ingress.yaml
```

**Check the Ingress:**

```bash
kubectl get ingress -n test
```

> ⚠️ **Note:** If a new load balancer IP is assigned, edit the Ingress and update the `host` field with the new IP.

---

## Configure Bitbucket Webhook

### Steps to Configure

1. Go to your Bitbucket repository
2. Navigate to **Repository Settings** → **Webhooks**
3. Click **Add webhook**
4. Configure the webhook:
   - **Name:** `Tekton Trigger`
   - **URL:** `http://bitbucket-listener.35.244.2.22.nip.io`
   - **Triggers:** Select **Repository push** (or whatever event your TriggerTemplate expects)
5. Save the webhook

🎉 **Done!** Now, whenever you push to the `main` branch, Bitbucket will trigger the Tekton pipeline automatically!

---

## Troubleshooting

### Common Issues

#### 1. Permission errors during push

**Symptoms:** Pipeline fails with permission denied when pushing to Artifact Registry

**Solutions:**
- Verify Workload Identity is enabled on both cluster and nodepools
- Check service account annotations and IAM bindings
- Verify the service account has `roles/artifactregistry.writer` role

```bash
# Check WI on cluster
gcloud container clusters describe <cluster-name> \
    --zone=<zone> \
    --format="value(workloadIdentityConfig.workloadPool)"

# Check WI on nodepool
gcloud container node-pools describe <nodepool-name> \
    --cluster=<cluster-name> \
    --zone=<zone> \
    --format="yaml(config.workloadMetadataConfig)"
```

#### 2. Webhook not triggering

**Symptoms:** Push to repository doesn't trigger pipeline

**Solutions:**
- Verify Ingress is accessible from the internet
- Check EventListener logs:
  ```bash
  kubectl logs -n test -l eventlistener=bitbucket-listener
  ```
- Verify webhook URL in Bitbucket settings matches your Ingress host
- Check webhook delivery history in Bitbucket

#### 3. Pipeline fails to clone repository

**Symptoms:** First task fails with authentication error

**Solutions:**
- Verify SSH keys are correctly configured
- Check git-credentials secret exists and is properly base64 encoded:
  ```bash
  kubectl get secret git-credentials -n test -o yaml
  ```
- Test SSH connection manually:
  ```bash
  ssh -T git@bitbucket.org
  ```
- Verify the private key has correct permissions (600)

#### 4. Build fails to push to Artifact Registry

**Symptoms:** Kaniko build succeeds but push fails

**Solutions:**
- Verify service account has correct IAM roles
- Check Workload Identity binding:
  ```bash
  kubectl describe sa tekton-sa -n test
  ```
- Verify Artifact Registry API is enabled:
  ```bash
  gcloud services list --filter="name:artifactregistry.googleapis.com"
  ```

---

## Summary

This guide covered:

✅ Workload Identity configuration for GKE  
✅ Installing Tekton Operator with Pipelines, Triggers, and Dashboard  
✅ Setting up SSH authentication with Bitbucket  
✅ Creating pipelines to clone repositories and read files  
✅ Building and pushing Docker images to Artifact Registry  
✅ Automating pipeline execution with Tekton Triggers  
✅ Exposing EventListener via Ingress for webhook integration  
✅ Configuring Bitbucket webhooks  

**Your CI/CD pipeline is now fully automated and ready to build and deploy on every push to your repository!** 🚀

---

## Additional Resources

- [Tekton Documentation](https://tekton.dev/docs/)
- [Tekton Catalog](https://hub.tekton.dev/)
- [GKE Workload Identity Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Bitbucket Webhooks Documentation](https://support.atlassian.com/bitbucket-cloud/docs/manage-webhooks/)

---

**Happy Building!** 🎉







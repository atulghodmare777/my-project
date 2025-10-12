# 🚀 Bitbucket Kubernetes Runner Autoscaler on GKE

**Complete Implementation & Troubleshooting Guide**

> Dynamically scale Bitbucket Pipeline runners on Google Kubernetes Engine with automatic authentication and pod management.

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Prerequisites](#-prerequisites)
- [Authentication Setup](#-step-1--choose-authentication-method)
  - [Option 1: OAuth Consumer](#-option-1--oauth-consumer-recommended)
  - [Option 2: API Token](#-option-2--api-token)
- [Repository Setup](#-step-2--clone-the-autoscaler-repository)
- [Configuration](#-step-3--configure-runners-and-scaling)
- [Credential Management](#-step-4--configure-credentials-via-kustomize)
- [Deployment](#-step-5--deploy-the-autoscaler)
- [Verification](#-step-6--verify-the-deployment)
- [Testing](#-step-7--test-with-bitbucket-pipeline)
- [Troubleshooting](#-troubleshooting)
- [Best Practices](#-best-practices)

---

## 🧩 Overview

The **Bitbucket Runner Autoscaler** dynamically creates and deletes Kubernetes pods that execute Bitbucket Pipelines, integrating **Bitbucket Cloud** with your **GKE cluster** to scale runners automatically based on pipeline load.

### Architecture Components

| Component | Namespace | Description |
|-----------|-----------|-------------|
| `runner-controller` | `bitbucket-runner-control-plane` | Handles communication with Bitbucket and manages runner jobs |
| `runner-controller-cleaner` | `bitbucket-runner-control-plane` | Cleans up stale or finished runner pods |
| `runner-*` pods | `default` | Actual Bitbucket runner agents executing pipeline steps |

### Resources

📦 **Docker Image:** [bitbucketpipelines/runners-autoscaler](https://hub.docker.com/r/bitbucketpipelines/runners-autoscaler/tags)  
📚 **Official Docs:** [Bitbucket Pipelines Runners](https://support.atlassian.com/bitbucket-cloud/docs/runners/)

---

## ✅ Prerequisites

Before starting, ensure you have:

- ☑️ **GKE cluster** with kubectl access
- ☑️ **Bitbucket workspace** with admin permissions
- ☑️ **kubectl** installed and configured
- ☑️ **Git** for cloning the repository
- ☑️ Basic knowledge of Kubernetes and Kustomize

---

## 🔐 Step 1 — Choose Authentication Method

The autoscaler supports two authentication options. Choose one based on your use case:

### 🏢 Option 1 — OAuth Consumer (Recommended)

**Best for:** Enterprise use, team environments, production workloads

#### Setup Steps:

1. Navigate to **Bitbucket → Workspace Settings → OAuth Consumers**
2. Click **Add consumer**
3. Configure the following:

   | Field | Value |
   |-------|-------|
   | **Name** | `gke-runner-autoscaler` |
   | **Callback URL** | `https://bitbucket.org/site/oauth2/callback` |
   | **URL** | `https://bitbucket.org` |
   | **Type** | **Private (Confidential)** ✅ |

4. Under **Permissions**, enable:
   - ✅ `Account: Read`
   - ✅ `Repository: Read`
   - ✅ `Pipeline: Write`
   - ✅ `Runner: Write`

5. Save and copy:
   - **Client ID**
   - **Client Secret**

> ⚠️ **Important:** Ensure the OAuth consumer is set to **Private (Confidential)**, not Public. Public consumers will fail with "Invalid Grant" errors.

---

### 🔑 Option 2 — API Token

**Best for:** Personal projects, workspace admin use, simpler setup

#### Setup Steps:

1. Go to **Bitbucket Account Settings → Security → API Tokens**
2. Click **Create API Token**
3. Provide a name: `gke-runner-autoscaler`
4. Assign the following scopes:
   - ✅ `read:repository:bitbucket`
   - ✅ `read:workspace:bitbucket`
   - ✅ `read:runner:bitbucket`
   - ✅ `write:runner:bitbucket`

5. Save and copy:
   - **Your Atlassian account email**
   - **API Token**

> 💡 **Tip:** API tokens must be created by a workspace admin to have proper permissions.

---

## 📦 Step 2 — Clone the Autoscaler Repository

```bash
git clone https://bitbucket.org/bitbucketpipelines/runners-autoscaler.git
cd runners-autoscaler/kustomize
```

### Repository Structure

```
kustomize/
├── base/
│   ├── cm-job-template.yaml
│   ├── deployment.yaml
│   ├── deployment-cleaner.yaml
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── rbac.yaml
│   └── secret.yaml              # Base secret (don't edit directly)
└── values/
    ├── kustomization.yaml       # Edit this for credentials
    └── runners_config.yaml      # Edit this for scaling settings
```

---

## ⚙️ Step 3 — Configure Runners and Scaling

Edit the runner configuration file:

```bash
vi values/runners_config.yaml
```

### Example Configuration

```yaml
constants:
  default_sleep_time_runner_setup: 10
  default_sleep_time_runner_delete: 5
  runner_api_polling_interval: 600
  runner_cool_down_period: 300

groups:
  - name: "Runner group 1"
    workspace: "{6321d246-a40a-4776-8497-372a41771e65}"
    labels:
      - "gke.runner"
    namespace: "default"
    strategy: "percentageRunnersIdle"
    parameters:
      min: 1
      max: 10
      scale_up_threshold: 0.5
      scale_down_threshold: 0.2
      scale_up_multiplier: 1.5
      scale_down_multiplier: 0.5
    resources:
      requests:
        memory: "2Gi"
        cpu: "1000m"
      limits:
        memory: "2Gi"
        cpu: "1000m"
```

### Configuration Parameters

| Parameter | Description | Recommended Value |
|-----------|-------------|-------------------|
| `min` | Minimum runners (warm pool) | `1` (prevents cold starts) |
| `max` | Maximum runners allowed | `10` |
| `scale_up_threshold` | When to create more runners | `0.5` (50% idle) |
| `scale_down_threshold` | When to remove runners | `0.2` (20% idle) |
| `namespace` | Where runner pods spawn | `default` |

### Finding Your Workspace UUID

```bash
curl -u <username>:<app-password> \
  https://api.bitbucket.org/2.0/workspaces/<workspace-id>
```

> 📝 **Note:** Use `namespace: default` for runner pods. The control-plane namespace is reserved for controllers.

---

## 🔧 Step 4 — Configure Credentials via Kustomize

### Step 4.1: Encode Credentials to Base64

Before editing the kustomization file, encode your credentials:

```bash
# For OAuth Consumer
echo -n "<client-id>" | base64
echo -n "<client-secret>" | base64

# For API Token
echo -n "<your-email>" | base64
echo -n "<api-token>" | base64
```

### Step 4.2: Edit Kustomization File

```bash
vi values/kustomization.yaml
```

Choose **one** of the following configurations:

---

### 🏢 OAuth Consumer Configuration

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../base

configMapGenerator:
  - name: runners-autoscaler-config
    files:
      - runners_config.yaml
    options:
      disableNameSuffixHash: true

namespace: bitbucket-runner-control-plane

commonLabels:
  app.kubernetes.io/part-of: runners-autoscaler

images:
  - name: bitbucketpipelines/runners-autoscaler
    newTag: 3.9.0     # Latest stable version

patches:
  - target:
      version: v1
      kind: Secret
      name: runner-bitbucket-credentials
    patch: |-
      - op: add
        path: /data/bitbucketOauthClientId
        value: "<BASE64_CLIENT_ID>"
      - op: add
        path: /data/bitbucketOauthClientSecret
        value: "<BASE64_CLIENT_SECRET>"

  - target:
      version: v1
      kind: Deployment
      labelSelector: "inject=runners-autoscaler-envs"
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env
        value:
          - name: BITBUCKET_OAUTH_CLIENT_ID
            valueFrom:
              secretKeyRef:
                key: bitbucketOauthClientId
                name: runner-bitbucket-credentials
          - name: BITBUCKET_OAUTH_CLIENT_SECRET
            valueFrom:
              secretKeyRef:
                key: bitbucketOauthClientSecret
                name: runner-bitbucket-credentials
```

---

### 🔑 API Token Configuration

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../base

configMapGenerator:
  - name: runners-autoscaler-config
    files:
      - runners_config.yaml
    options:
      disableNameSuffixHash: true

namespace: bitbucket-runner-control-plane

commonLabels:
  app.kubernetes.io/part-of: runners-autoscaler

images:
  - name: bitbucketpipelines/runners-autoscaler
    newTag: 3.9.0     # Latest stable version

patches:
  - target:
      version: v1
      kind: Secret
      name: runner-bitbucket-credentials
    patch: |-
      - op: add
        path: /data/atlassianAccountEmail
        value: "<BASE64_EMAIL>"
      - op: add
        path: /data/atlassianApiToken
        value: "<BASE64_API_TOKEN>"

  - target:
      version: v1
      kind: Deployment
      labelSelector: "inject=runners-autoscaler-envs"
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env
        value:
          - name: ATLASSIAN_ACCOUNT_EMAIL
            valueFrom:
              secretKeyRef:
                key: atlassianAccountEmail
                name: runner-bitbucket-credentials
          - name: ATLASSIAN_API_TOKEN
            valueFrom:
              secretKeyRef:
                key: atlassianApiToken
                name: runner-bitbucket-credentials
```

---

## 🚀 Step 5 — Deploy the Autoscaler

Navigate to the values directory and apply:

```bash
cd runners-autoscaler/kustomize/values
kubectl apply -k .
```

### What This Does:

✅ Creates the `bitbucket-runner-control-plane` namespace  
✅ Deploys controller and cleaner pods  
✅ Applies RBAC permissions  
✅ Creates ConfigMaps with runner configuration  
✅ Injects credentials as Kubernetes Secrets  
✅ Starts the autoscaler

---

## 🔍 Step 6 — Verify the Deployment

### Check Control Plane Pods

```bash
kubectl get pods -n bitbucket-runner-control-plane
```

**Expected Output:**

```
NAME                                        READY   STATUS    RESTARTS   AGE
runner-controller-xxxxx                     1/1     Running   0          2m
runner-controller-cleaner-xxxxx             1/1     Running   0          2m
```

### Monitor Controller Logs

```bash
kubectl logs -l app=runner-controller -n bitbucket-runner-control-plane -f
```

**Success Indicators:**

```
INFO: Runner created on Bitbucket workspace: your-workspace
✔ Successfully setup runner UUID {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}
INFO: Polling for pending jobs...
```

### Check Runner Pods

```bash
kubectl get pods -n default
```

**Expected Output:**

```
NAME                READY   STATUS    RESTARTS   AGE
runner-xxxxxx       1/1     Running   0          30s
```

### Verify in Bitbucket UI

1. Go to **Workspace Settings → Runners**
2. You should see your runner listed as **ONLINE**
3. Note the runner labels (e.g., `gke.runner`)

---

## 🧪 Step 7 — Test with Bitbucket Pipeline

### Step 7.1: Create Pipeline File

In your repository, create `.bitbucket-pipelines.yml`:

```yaml
pipelines:
  default:
    - step:
        name: "Test GKE Runner"
        runs-on:
          - self.hosted
          - gke.runner
        script:
          - echo "✅ Running on Bitbucket GKE Kubernetes Runner"
          - echo "👤 User:" $(whoami)
          - echo "💻 Hostname:" $(hostname)
          - echo "🌍 Cluster Info:" $(kubectl version --client --short 2>/dev/null || echo "kubectl not available")
          - sleep 5
          - echo "🎉 Pipeline executed successfully!"
```

### Step 7.2: Commit and Push

```bash
git add .bitbucket-pipelines.yml
git commit -m "Add GKE runner test pipeline"
git push
```

### Step 7.3: Verify Execution

Go to **Bitbucket → Pipelines** and check the output:

```
✅ Running on Bitbucket GKE Kubernetes Runner
👤 User: root
💻 Hostname: runner-a1b2c3d4
🎉 Pipeline executed successfully!
```

---

## ⚠️ Troubleshooting

### Common Issues and Solutions

| Issue | Possible Cause | Resolution |
|-------|----------------|------------|
| **Invalid Grant Error** | OAuth consumer created as Public | Recreate as **Private (Confidential)** |
| **Missing Callback URL** | OAuth callback URL not set | Add `https://bitbucket.org/site/oauth2/callback` |
| **Bad Request (Secret)** | Incorrect Base64 encoding | Re-encode credentials: `echo -n "value" \| base64` |
| **Pipeline Queued Forever** | Runner not linked to repository | Link via **Repo → Settings → Runners** |
| **Runner Shows Idle** | Label mismatch in pipeline | Ensure `self.hosted` and `gke.runner` are used |
| **Pods Not Spawning** | Wrong namespace in config | Use `namespace: default` for runners |
| **API Token Not Working** | Token created by non-admin | Create token with workspace admin account |
| **Controller Crashloop** | Invalid credentials | Check logs: `kubectl logs -n bitbucket-runner-control-plane` |
| **Runner Offline** | Network/firewall issues | Verify cluster has internet access to Bitbucket API |

### Debugging Commands

```bash
# Check controller logs
kubectl logs -l app=runner-controller -n bitbucket-runner-control-plane --tail=100

# Check cleaner logs
kubectl logs -l app=runner-controller-cleaner -n bitbucket-runner-control-plane --tail=100

# Describe controller deployment
kubectl describe deployment runner-controller -n bitbucket-runner-control-plane

# Check secrets
kubectl get secrets -n bitbucket-runner-control-plane

# View runner pods
kubectl get pods -n default -l app=runner

# Check events
kubectl get events -n bitbucket-runner-control-plane --sort-by='.lastTimestamp'
```

### Re-deploying After Changes

```bash
# Delete existing deployment
kubectl delete -k .

# Wait for cleanup
kubectl get pods -n bitbucket-runner-control-plane --watch

# Re-apply
kubectl apply -k .
```

---

## ✅ Validation Checklist

Use this checklist to ensure everything is working:

| Check | Expected Result | Status |
|-------|----------------|--------|
| **Bitbucket UI** | Runner appears as **ONLINE** | ☐ |
| **GKE Control Plane** | Controller pods **Running** | ☐ |
| **Runner Pods** | Dynamically spawning in `default` namespace | ☐ |
| **Pipeline Execution** | Successfully completes on self-hosted runner | ☐ |
| **Autoscaling** | Adjusts between min and max (1–10 runners) | ☐ |
| **Logs** | No errors in controller logs | ☐ |

---

## 💡 Best Practices

### Security

- 🔒 Use **Private OAuth Consumer** for production environments
- 🔑 Rotate API tokens regularly
- 🛡️ Apply least-privilege RBAC policies
- 📝 Store sensitive values in external secret managers (e.g., Google Secret Manager)

### Performance

- ⚡ Keep `min: 1` to maintain a warm runner pool (reduces cold-start latency)
- 📊 Monitor resource usage and adjust `requests`/`limits` accordingly
- 🔄 Set appropriate `cool_down_period` to prevent thrashing

### Maintenance

- 📦 Monitor new versions on [Docker Hub](https://hub.docker.com/r/bitbucketpipelines/runners-autoscaler/tags)
- 🔄 Test upgrades in a non-production environment first
- 📋 Keep runner labels simple and consistent (e.g., `gke.runner`)
- 🚫 Don't modify base manifests — use overlays in `values/` directory
- 🗂️ Avoid using `bitbucket-runner-control-plane` namespace for runner pods

### Scaling Strategy

```yaml
# Conservative (cost-optimized)
min: 1, max: 5, scale_up_threshold: 0.3

# Balanced (recommended)
min: 1, max: 10, scale_up_threshold: 0.5

# Aggressive (performance-optimized)
min: 2, max: 20, scale_up_threshold: 0.7
```

---

## 📊 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Bitbucket Cloud                         │
│  ┌──────────────┐         ┌───────────────┐               │
│  │   Pipeline   │────────▶│ Runner Queue  │               │
│  └──────────────┘         └───────┬───────┘               │
└──────────────────────────────────┼─────────────────────────┘
                                    │ HTTPS/API
                                    ▼
┌─────────────────────────────────────────────────────────────┐
│              GKE Cluster (your-cluster)                     │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐  │
│  │    bitbucket-runner-control-plane namespace         │  │
│  │                                                       │  │
│  │  ┌─────────────────────┐  ┌────────────────────┐   │  │
│  │  │ runner-controller   │  │ runner-cleaner     │   │  │
│  │  │ - Polls Bitbucket   │  │ - Removes stale    │   │  │
│  │  │ - Creates runners   │  │   runner pods      │   │  │
│  │  └──────────┬──────────┘  └────────────────────┘   │  │
│  └─────────────┼────────────────────────────────────────┘  │
│                │                                            │
│                ▼                                            │
│  ┌─────────────────────────────────────────────────────┐  │
│  │          default namespace                          │  │
│  │                                                       │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │  │
│  │  │ runner-1 │  │ runner-2 │  │ runner-N │          │  │
│  │  │ (pod)    │  │ (pod)    │  │ (pod)    │          │  │
│  │  └──────────┘  └──────────┘  └──────────┘          │  │
│  │                                                       │  │
│  │  ↕ Scale between min=1 and max=10                   │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Summary

You've successfully deployed the Bitbucket Runner Autoscaler on GKE! Your setup now:

✅ Automatically scales runners based on pipeline demand  
✅ Supports both OAuth Consumer and API Token authentication  
✅ Maintains a warm pool of runners for fast pipeline execution  
✅ Cleans up finished runner pods automatically  
✅ Integrates seamlessly with Bitbucket Cloud pipelines

### Next Steps

1. Monitor runner performance and adjust scaling parameters
2. Set up monitoring/alerting for runner health
3. Configure additional runner groups for different workloads
4. Implement resource quotas for cost control

---

## 📚 Additional Resources

- 📖 [Bitbucket Pipelines Runners Documentation](https://support.atlassian.com/bitbucket-cloud/docs/runners/)
- 🐳 [Docker Hub - Runners Autoscaler](https://hub.docker.com/r/bitbucketpipelines/runners-autoscaler)
- ☸️ [Kubernetes Kustomize Documentation](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
- 🔧 [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)

---

**Last Updated:** October 2025  
**Version:** 3.9.0  
**Tested On:** GKE 1.28+

---

### 📝 License

This documentation is based on the official Bitbucket Pipelines Runners Autoscaler project.  
Please refer to the [official repository](https://bitbucket.org/bitbucketpipelines/runners-autoscaler) for license information.

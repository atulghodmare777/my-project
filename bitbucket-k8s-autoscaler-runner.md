# 🚀 Bitbucket Kubernetes Runner Autoscaler on GKE  
### *Accurate Implementation & Troubleshooting Documentation*

This document outlines the **real-world steps** performed to deploy and validate  
the **Bitbucket Runners Autoscaler** on **Google Kubernetes Engine (GKE)** —  
including OAuth setup, file modifications, deployment, and troubleshooting.

---

## 🧩 Overview

The **Bitbucket Runner Autoscaler** dynamically manages Kubernetes pods that execute Bitbucket Pipelines.  
It connects Bitbucket Cloud to your GKE cluster and scales runners automatically.

| Component | Namespace | Description |
|------------|------------|-------------|
| `runner-controller` | `bitbucket-runner-control-plane` | Handles communication with Bitbucket and creates/deletes runner pods. |
| `runner-controller-cleaner` | `bitbucket-runner-control-plane` | Cleans up completed or idle runner pods. |
| `runner-*` pods | `default` | Actual Bitbucket runner agents that execute pipeline steps. |

---

## 🧾 Step 1 — Create Bitbucket OAuth Consumer

Before deploying the autoscaler, we created a **Bitbucket OAuth Consumer**.  
This is essential for authenticating the autoscaler to Bitbucket’s API.

1. Navigate to **Bitbucket → Workspace Settings → OAuth Consumers**  
2. Click **Add consumer** and fill in:
   - **Name:** `gke-runner-autoscaler`
   - **Callback URL:** `https://bitbucket.org`
   - **URL:** `https://bitbucket.org`
   - **Type:** Select **Private (Confidential)** (⚠️ required)
3. Under **Permissions**, enable:
   - ✅ `Account: Read`
   - ✅ `Repository: Read`
   - ✅ `Pipeline: Write`
   - ✅ `Runner: Write`
4. Click **Save**  
5. Copy:
   - **Key (Client ID)**
   - **Secret (Client Secret)**  

You’ll use these in the next step.

---

## 📦 Step 2 — Clone the Bitbucket Autoscaler Repository

```bash
git clone https://bitbucket.org/bitbucketpipelines/runners-autoscaler.git
cd runners-autoscaler/kustomize
After cloning, verify the structure:

csharp
Copy code
kustomize/
├── base/
│   ├── cm-job-template.yaml
│   ├── deployment.yaml
│   ├── deployment-cleaner.yaml
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── rbac.yaml
│   ├── secret.yaml               ← Already present (we did NOT edit this)
└── values/
    ├── kustomization.yaml        ← We edited this to inject OAuth credentials
    └── runners_config.yaml       ← We edited this to configure scaling and namespace
⚙️ Step 3 — Configure the Autoscaler
🧩 Edit values/runners_config.yaml
This file defines how the autoscaler connects to Bitbucket, manages scaling, and sets runner labels.

yaml
Copy code
constants:
  default_sleep_time_runner_setup: 10
  default_sleep_time_runner_delete: 5
  runner_api_polling_interval: 600
  runner_cool_down_period: 300

groups:
  - name: "Runner group 1"
    workspace: "{6321d246-a40a-4776-8497-372a41771e65}"  # Workspace UUID (use braces)
    # Get this via: https://api.bitbucket.org/2.0/workspaces/<your-workspace-id>
    labels:
      - "gke.runner"
    namespace: "default"  # Target namespace for runner pods
    strategy: "percentageRunnersIdle"
    parameters:
      min: 1               # Keep one warm runner (prevents cold start failures)
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
🧠 Notes:

workspace: The Bitbucket workspace UUID (inside {}).

labels: Custom label for runners. Only gke.runner used (Bitbucket auto-adds linux, self.hosted).

namespace: Use default — control-plane namespace is reserved.

min: 1: Keeps one standby runner for fast builds.

🔐 Step 4 — Inject OAuth Credentials via Kustomize
We didn’t create a secret manually.
Instead, we updated values/kustomization.yaml to patch the secret using Kustomize.

🧭 Generate Base64 Credentials
Encode the OAuth credentials:

bash
Copy code
echo -n "<your-client-id>" | base64
echo -n "<your-client-secret>" | base64
🛠️ Update values/kustomization.yaml
We uncommented and edited two patch sections:
(1) Secret injection and (2) Deployment environment variables.

yaml
Copy code
patches:
  - target:
      version: v1
      kind: Secret
      name: runner-bitbucket-credentials
    patch: |-
      ### Inject OAuth credentials ###
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
📘 Notes:

We edited only values/kustomization.yaml.

The base secret (base/secret.yaml) remained unchanged.

Kustomize automatically generates the runner-bitbucket-credentials secret on deployment.

🚀 Step 5 — Deploy the Autoscaler
Apply everything from the values directory:

bash
Copy code
cd runners-autoscaler/kustomize/values
kubectl apply -k .
This creates:

Namespace: bitbucket-runner-control-plane

Controller deployments and cleaner jobs

ConfigMaps and RBAC resources

Patched OAuth credentials secret

Autoscaler ready for Bitbucket connection

🔍 Step 6 — Verify Deployment
🧩 Check controller pods
bash
Copy code
kubectl get pods -n bitbucket-runner-control-plane
Expected:

sql
Copy code
runner-controller-xxxxx           Running
runner-controller-cleaner-xxxxx   Running
📜 View logs
bash
Copy code
kubectl logs -l app=runner-controller -n bitbucket-runner-control-plane -f
Sample successful output:

arduino
Copy code
INFO: Runner created on Bitbucket workspace: woodpeckernew
✔ Successfully setup runner UUID {...}
🏃 Check active runners
bash
Copy code
kubectl get pods -n default
Example:

sql
Copy code
runner-5972c0fe-880b-5eea-a0b7-0d5837d9d48b   2/2   Running   0   3m
🧪 Step 7 — Test the Runner with a Pipeline
Create bitbucket-pipelines.yml in a repository under the same workspace:

yaml
Copy code
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
          - sleep 5
          - echo "🎉 Pipeline executed successfully!"
✅ Result in Bitbucket UI:

sql
Copy code
✅ Running on Bitbucket GKE Kubernetes Runner
👤 User: root
💻 Hostname: runner-xxxxxx
🎉 Pipeline executed successfully!
⚠️ Common Issues & Fixes
Issue	Description	Resolution
Invalid Grant (public consumer)	Created OAuth consumer as Public.	Recreate it as Private (Confidential).
Missing callback URL	Bitbucket requires at least one callback.	Added https://bitbucket.org/site/oauth2/callback.
Missing scopes	Lacked runner:write.	Added account:write, repository:read, pipeline:write, runner:write.
Reserved namespace error	Runners spawned in control-plane namespace.	Changed to namespace: default in config.
Invalid label format	Used invalid characters or linux.shell.	Kept only gke.runner.
Multiple platform labels	Bitbucket enforces one platform label.	Removed additional platform labels.
400 Bad Request (Secret misconfig)	Incorrect OAuth values.	Fixed via correct base64 in values/kustomization.yaml.
Runner cold start delay	min: 0 deletes all runners.	Set min: 1 to keep a standby runner.

✅ Final Validation
🧩 Bitbucket UI
yaml
Copy code
Runner name: Runner group 1
Runner UUID: {5972c0fe-880b-5eea-a0b7-0d5837d9d48b}
Labels: self.hosted, linux, gke.runner
Status: ONLINE
☸️ Cluster Pods
bash
Copy code
kubectl get pods -A | grep runner
bitbucket-runner-control-plane   runner-controller-xxxxx           Running
bitbucket-runner-control-plane   runner-controller-cleaner-xxxxx   Running
default                          runner-5972c0fe-880b-5eea-a0b7-0d5837d9d48b   Running
🧠 Summary
Aspect	Status	Notes
OAuth Integration	✅	Configured via Kustomize patches
Controller Pods	✅	Running in control-plane namespace
Runner Pods	✅	Dynamically spawned in default
Pipeline Execution	✅	Verified via test pipeline
Autoscaling	✅	Fully functional (1–10 runners)

💡 Best Practices
Use Private (Confidential) OAuth consumers with correct scopes.

Keep labels simple (gke.runner) — Bitbucket adds platform ones automatically.

Avoid control-plane namespace for runners.

Maintain at least 1 warm runner for faster startup.

Store credentials via Kustomize overlay, not plain YAML or CLI secrets.


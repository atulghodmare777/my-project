# 🚀 Bitbucket Kubernetes Runner Autoscaler on GKE  
### *Accurate Implementation & Troubleshooting Documentation*

This document describes the **complete setup and validation** of the **Bitbucket Runner Autoscaler** on **Google Kubernetes Engine (GKE)** —  
covering both **OAuth Consumer** and **API Token** authentication methods, file modifications, deployment steps, and troubleshooting.

---

## 🧩 Overview

The **Bitbucket Runner Autoscaler** dynamically creates and deletes Kubernetes pods that execute Bitbucket Pipelines.  
It integrates **Bitbucket Cloud** with your **GKE cluster** to scale runners automatically based on pipeline load.

| Component | Namespace | Description |
|------------|------------|-------------|
| `runner-controller` | `bitbucket-runner-control-plane` | Handles communication with Bitbucket and manages runner jobs. |
| `runner-controller-cleaner` | `bitbucket-runner-control-plane` | Cleans up stale or finished runner pods. |
| `runner-*` pods | `default` | Actual Bitbucket runner agents executing pipeline steps. |

📦 **Official Docker image source:**  
🔗 [bitbucketpipelines/runners-autoscaler on Docker Hub](https://hub.docker.com/r/bitbucketpipelines/runners-autoscaler/tags)

---

## 🧾 Step 1 — Choose Your Authentication Method

The autoscaler supports two authentication options:  
1. **OAuth Consumer (recommended for enterprise use)**  
2. **Atlassian API Token (simpler for personal/workspace use)**  

Both methods are configured in the same `values/kustomization.yaml` file — just uncomment the option you want.

---

### 🔐 Option 1 — Using OAuth Consumer

#### Steps:
1. Go to **Bitbucket → Workspace Settings → OAuth Consumers**  
2. Click **Add consumer**
3. Fill the fields:
   - **Name:** `gke-runner-autoscaler`
   - **Callback URL:** `https://bitbucket.org`
   - **URL:** `https://bitbucket.org`
   - **Type:** **Private (Confidential)** ✅
4. Under **Permissions**, enable:
   - `Account: Read`
   - `Repository: Read`
   - `Pipeline: Write`
   - `Runner: Write`
5. Save and copy:
   - **Client ID**
   - **Client Secret**

---

### 🔑 Option 2 — Using API Token

#### Steps:
1. Go to **Bitbucket Account Settings → Security → API Tokens**
2. Click **Create API Token**
3. Give a name (e.g., `gke-runner-autoscaler`)
4. Assign the following scopes:
   - ✅ `read:repository:bitbucket`
   - ✅ `read:workspace:bitbucket`
   - ✅ `read:runner:bitbucket`
   - ✅ `write:runner:bitbucket`
5. Save and copy the token.  
   You’ll need this and your Atlassian account email.

---

## 📦 Step 2 — Clone the Autoscaler Repository

```bash
git clone https://bitbucket.org/bitbucketpipelines/runners-autoscaler.git
cd runners-autoscaler/kustomize
Structure after cloning
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
│   ├── secret.yaml              ← Already present (don’t edit)
└── values/
    ├── kustomization.yaml       ← We edit this for credentials
    └── runners_config.yaml      ← We edit this for scaling and workspace
⚙️ Step 3 — Configure Runners and Scaling
Edit:

bash
Copy code
vi values/runners_config.yaml
Example
yaml
Copy code
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
🧠 Notes

Use namespace: default (the control-plane namespace is reserved).

Keep min: 1 for one warm runner to prevent cold-start latency.

Workspace UUID can be fetched using:
https://api.bitbucket.org/2.0/workspaces/<workspace-id>

🔧 Step 4 — Configure Credentials via Kustomize
Before editing, encode credentials in Base64:

bash
Copy code
echo -n "<client-id>" | base64
echo -n "<client-secret>" | base64
echo -n "<your-email>" | base64
echo -n "<api-token>" | base64
🧩 Full Kustomization for OAuth Consumer
yaml
Copy code
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
    newTag: 3.9.0     # Recommended tag (latest stable)

patches:
  - target:
      version: v1
      kind: Secret
      name: runner-bitbucket-credentials
    patch: |-
      ### OAuth Authentication ###
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
      ### OAuth Environment Variables ###
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
🧩 Full Kustomization for API Token
yaml
Copy code
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
    newTag: 3.9.0     # Recommended tag (latest stable)

patches:
  - target:
      version: v1
      kind: Secret
      name: runner-bitbucket-credentials
    patch: |-
      ### API Token Authentication ###
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
      ### API Token Environment Variables ###
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
🚀 Step 5 — Deploy the Autoscaler
bash
Copy code
cd runners-autoscaler/kustomize/values
kubectl apply -k .
✅ This will:

Create the namespace bitbucket-runner-control-plane

Deploy controller & cleaner pods

Apply RBAC and ConfigMaps

Inject credentials as Kubernetes secrets

Start the autoscaler

🔍 Step 6 — Verify the Deployment
bash
Copy code
kubectl get pods -n bitbucket-runner-control-plane
✅ Expected:

sql
Copy code
runner-controller-xxxxx           Running
runner-controller-cleaner-xxxxx   Running
Check logs:

bash
Copy code
kubectl logs -l app=runner-controller -n bitbucket-runner-control-plane -f
You should see:

arduino
Copy code
INFO: Runner created on Bitbucket workspace: woodpeckernew
✔ Successfully setup runner UUID {...}
List runner pods:

bash
Copy code
kubectl get pods -n default
🧪 Step 7 — Test with Bitbucket Pipeline
Create .bitbucket-pipelines.yml:

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
Expected Bitbucket output:

sql
Copy code
✅ Running on Bitbucket GKE Kubernetes Runner
👤 User: root
💻 Hostname: runner-xxxxxx
🎉 Pipeline executed successfully!
⚠️ Common Issues & Fixes
Issue	Description	Resolution
Invalid Grant	OAuth consumer created as Public	Recreate as Private
Missing callback URL	Required by Bitbucket	Add https://bitbucket.org/site/oauth2/callback
Bad Request (Secret misconfig)	Wrong base64 or syntax	Re-encode credentials
Pipeline queued forever	Runner not linked to repo	Link via Repo → Settings → Runners
Runner idle	Label mismatch	Use self.hosted & gke.runner
Pods not spawning	Wrong namespace	Use namespace: default
API token not working	Token from non-admin	Create with workspace admin account

✅ Final Validation
Check	Expected Result
Bitbucket UI	Runner appears as ONLINE
GKE Control Plane	Controller pods running
Runner Pods	Dynamically spawning in default
Pipeline	Executes successfully
Autoscaling	Adjusts 1–10 runners automatically

💡 Best Practices
Use Private OAuth Consumer or Admin API Token for reliability.

Keep one warm runner (min: 1) to reduce build wait time.

Don’t modify base manifests — use overlays (values/).

Use simple labels like gke.runner only.

Avoid using bitbucket-runner-control-plane for runner pods.

Monitor new versions on Docker Hub.

✅ Deployment Complete:
Your Bitbucket Runners Autoscaler is now live on GKE — supporting both OAuth and API Token authentication seamlessly.

yaml
Copy code

---

Would you like me to append a small **“Troubleshooting: Runner Online but Pipeline Stuck in Queue”** section at the end (as a ready-to-commit `.md` addition)?  
It fits naturally as the final diagnostic guide after this deployment doc.







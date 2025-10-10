# 🚀 Bitbucket Kubernetes Runner Autoscaler on GKE  
### *Accurate Setup Documentation (Actual Implementation & Troubleshooting)*

This document details the **exact implementation steps** performed to set up the  
**Bitbucket Runners Autoscaler** on **Google Kubernetes Engine (GKE)** — including  
the real file edits, deployment sequence, and issues encountered (with resolutions).

---

## 🧩 Overview

The **Bitbucket Runner Autoscaler** dynamically creates and deletes Kubernetes pods that run Bitbucket Pipelines builds.

| Component | Namespace | Description |
|------------|------------|-------------|
| `runner-controller` | `bitbucket-runner-control-plane` | Manages communication with Bitbucket and creates/deletes runner pods. |
| `runner-controller-cleaner` | `bitbucket-runner-control-plane` | Cleans up stale or terminated runner pods. |
| `runner-*` pods | `default` | Execute actual Bitbucket pipeline steps (Docker-in-Docker). |

---

## 📁 Repository & File Structure

We cloned the **official Bitbucket Runners Autoscaler** repository:

```bash
git clone https://bitbucket.org/bitbucketpipelines/runners-autoscaler.git
cd runners-autoscaler/kustomize
After cloning, the relevant structure was:

kotlin
Copy code
kustomize/
├── base/
│   ├── cm-job-template.yaml
│   ├── deployment.yaml
│   ├── deployment-cleaner.yaml
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── rbac.yaml
│   ├── secret.yaml               ← Already present (we didn’t edit this)
└── values/
    ├── kustomization.yaml        ← We edited this to inject OAuth credentials
    └── runners_config.yaml       ← We edited this to configure scaling behavior
⚙️ Configuration Changes
1️⃣ Edit values/runners_config.yaml
This file controls autoscaler logic, Bitbucket workspace connection, labels,
and scaling parameters.

vi runners_config.yaml
constants:
  default_sleep_time_runner_setup: 10
  default_sleep_time_runner_delete: 5
  runner_api_polling_interval: 600
  runner_cool_down_period: 300

groups:
  - name: "Runner group 1"
    workspace: "{6321d246-a40a-4776-8497-372a41771e65}"  # we can get it by pasting url in browser https://api.bitbucket.org/2.0/workspaces/workspace_id , replace workspace id in url
    labels:
      - "gke.runner"
    namespace: "default"  # Namespace where runner pods will be created
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

🧠 Explanation:
workspace: UUID of Bitbucket workspace.

labels: Custom runner labels. Only gke.runner was used to avoid conflicts.

namespace: We used default to prevent control-plane namespace errors.

min: 1: Keeps one warm runner ready (prevents cold-start build failures).

Scaling happens dynamically based on pipeline activity.

Encode the oauth consumer
echo -n "your-client-id" | base64
echo -n "your-client-secret" | base64

Then we uncommented the environment patch that injects these values into
2️⃣ Edit values/kustomization.yaml

We uncommented at 2 places in this file first in kind secret and second in kind deployment and edited the patch section like this:

vi kustomization.yaml
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

The runner-bitbucket-credentials Secret gets generated automatically when applying Kustomize.

We only edited values/kustomization.yaml, not any files under base/.

This ensures credentials are version-controlled safely via the overlay, not hardcoded in base.

🚀 Deployment
Once the above files were edited, we deployed directly from the values directory:

bash
Copy code
cd runners-autoscaler/kustomize/values
kubectl apply -k .
This applied all manifests and created the following components:

Namespace: bitbucket-runner-control-plane

Deployments: runner-controller, runner-controller-cleaner

ConfigMaps: job templates, runner configuration

Secret: runner-bitbucket-credentials (patched automatically)

Autoscaler ready to connect to Bitbucket

✅ Verification Steps
🧩 Check control plane pods
bash
Copy code
kubectl get pods -n bitbucket-runner-control-plane
Expected output:

sql
Copy code
runner-controller-xxxxxx           Running
runner-controller-cleaner-xxxxxx   Running
📋 Controller logs
bash
Copy code
kubectl logs -l app=runner-controller -n bitbucket-runner-control-plane -f
You should see:

csharp
Copy code
INFO: Runner created on Bitbucket workspace: woodpeckernew
INFO: Job created. status=runner-<uuid>
✔ Successfully setup runner UUID {...} on workspace woodpeckernew
🏃 Runner pods in action
bash
Copy code
kubectl get pods -n default
Example output:

sql
Copy code
runner-5972c0fe-880b-5eea-a0b7-0d5837d9d48b   2/2   Running   0   3m
🧪 Sample Bitbucket Pipeline Test
We used this file to confirm the runner execution:

bitbucket-pipelines.yml

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
🟢 Result in Bitbucket UI:

sql
Copy code
✅ Running on Bitbucket GKE Kubernetes Runner
👤 User: root
💻 Hostname: runner-xxxxxx
🎉 Pipeline executed successfully!
⚠️ Issues Encountered & Resolutions
Issue	Description	Resolution
Invalid Grant (public consumer)	Bitbucket OAuth consumer was created as Public.	Recreated it as Private (Confidential).
No callback URI defined	Bitbucket required a callback URL.	Added https://bitbucket.org/site/oauth2/callback.
Missing privilege scopes	OAuth lacked runner:write permission.	Added runner:write, pipeline:write, repository:read, account:write.
Namespace reserved error	Used bitbucket-runner-control-plane for runners.	Updated to namespace: default in runners_config.yaml.
Invalid labels (Bad Request)	Used linux.shell and invalid characters.	Kept only gke.runner (Bitbucket adds linux & self.hosted automatically).
Multiple platform labels	More than one platform label sent.	Removed platform labels from config.
400 Bad Request during runner creation	Misconfigured secret values.	Fixed by editing values/kustomization.yaml correctly (base64 credentials).
Cold start with min: 0	Runner took time to spin up after idle.	Kept min: 1 to maintain a warm standby runner.

🧾 Final Validation
✅ Bitbucket Workspace UI:

yaml
Copy code
Runner name: Runner group 1
Runner UUID: {5972c0fe-880b-5eea-a0b7-0d5837d9d48b}
Labels: self.hosted, linux, gke.runner
Status: ONLINE
✅ Cluster Pods:

bash
Copy code
kubectl get pods -A | grep runner
bitbucket-runner-control-plane   runner-controller-xxxxxx           Running
bitbucket-runner-control-plane   runner-controller-cleaner-xxxxxx   Running
default                          runner-5972c0fe-880b-5eea-a0b7-0d5837d9d48b   Running
✅ Autoscaler Logs:
Showed correct scaling activity and runner lifecycle.

🧠 Summary
Aspect	Status	Notes
Bitbucket OAuth	✅ Working	Configured via Kustomize patch
Runner Controller	✅ Running	Communicates with Bitbucket API
Runner Pods	✅ Spawning dynamically	Lives in default namespace
Pipeline Execution	✅ Successful	Verified via test pipeline
Autoscaling	✅ Functional	Scales between 1–10 runners

📘 Best Practices
Keep one warm runner (min: 1) for faster first builds.

Avoid editing base manifests — use overlays (values/).

Ensure OAuth consumer is private and has all required scopes.

Keep label names lowercase with dots only (gke.runner).

Avoid placing runners in the control-plane namespace.

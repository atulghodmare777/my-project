Install ingress + cert-manager

Bitbucket webhooks need a public HTTPS endpoint. We install nginx ingress + cert-manager for that.

# Ingress controller
kubectl create ns ingress-nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx

# Cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.crds.yaml
kubectl create ns cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager -n cert-manager
Why: This lets us expose Tekton EventListener (for Bitbucket) and Tekton Dashboard (for humans).

Install Tekton Operator

The Operator installs Pipelines, Triggers, and Dashboard in one go.
kubectl apply -f https://storage.googleapis.com/tekton-releases/operator/latest/release.yaml

Create config:
# tektonconfig.yaml
apiVersion: operator.tekton.dev/v1alpha1
kind: TektonConfig
metadata:
  name: config
spec:
  profile: all
  targetNamespace: tekton-pipelines


kubectl apply -f tektonconfig.yaml
kubectl get pods -n tekton-pipelines --watch


Why: Profile all ensures you get Pipelines (to run CI), Triggers (to respond to webhooks), Dashboard (to view runs).

ServiceAccounts & Workload Identity

We need two Kubernetes ServiceAccounts:

tekton-triggers-sa: lets EventListener create PipelineRuns.

kaniko-sa: runs Kaniko with a Google Service Account (GSA) bound via Workload Identity.

kubectl create ns tekton-pipelines || true

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-triggers-sa
  namespace: tekton-pipelines
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kaniko-sa
  namespace: tekton-pipelines
YAML


Now create and bind the GSA:
PROJECT=your-gcp-project
GSA=tekton-kaniko-gsa
KSA=kaniko-sa
KSA_NS=tekton-pipelines

# Create GSA
gcloud iam service-accounts create $GSA --project $PROJECT

# Give permission to push images
gcloud projects add-iam-policy-binding $PROJECT \
  --member="serviceAccount:${GSA}@${PROJECT}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Bind GSA to KSA
gcloud iam service-accounts add-iam-policy-binding \
  ${GSA}@${PROJECT}.iam.gserviceaccount.com \
  --member="serviceAccount:${PROJECT}.svc.id.goog[${KSA_NS}/${KSA}]" \
  --role="roles/iam.workloadIdentityUser"

# Annotate the KSA
kubectl annotate serviceaccount ${KSA} -n ${KSA_NS} \
  iam.gke.io/gcp-service-account=${GSA}@${PROJECT}.iam.gserviceaccount.com

Why: Workload Identity = secure, keyless authentication. Kaniko pods running with kaniko-sa can now push images to Artifact Registry.

Step 5 — Define Pipeline (clone + Kaniko build & push)

Save as pipeline-build-push.yaml.
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: build-push-pipeline
  namespace: tekton-pipelines
spec:
  params:
    - name: gitrepositoryurl
      type: string
    - name: gitrevision
      type: string
      default: "main"
    - name: image
      type: string
  workspaces:
    - name: shared-data
  tasks:
    - name: clone
      taskSpec:
        params:
          - name: url
          - name: revision
            default: "main"
        workspaces:
          - name: output
        steps:
          - name: git-clone
            image: alpine/git
            script: |
              #!/bin/sh
              git clone --depth 1 --branch $(params.revision) $(params.url) $(workspaces.output.path)/source
      params:
        - name: url
          value: $(params.gitrepositoryurl)
        - name: revision
          value: $(params.gitrevision)
      workspaces:
        - name: output
          workspace: shared-data
    - name: build
      runAfter: [clone]
      taskSpec:
        params:
          - name: IMAGE
        workspaces:
          - name: source
        steps:
          - name: kaniko
            image: gcr.io/kaniko-project/executor:latest
            args:
              - "--context=$(workspaces.source.path)/source"
              - "--dockerfile=$(workspaces.source.path)/source/Dockerfile"
              - "--destination=$(params.IMAGE)"
      params:
        - name: IMAGE
          value: $(params.image)
      workspaces:
        - name: source
          workspace: shared-data

kubectl apply -f pipeline-build-push.yaml

Why: This pipeline clones your Bitbucket repo, then builds and pushes its Dockerfile image using Kaniko.

Step 6 — Create Triggers

Triggers wire Bitbucket webhooks to PipelineRuns. Save as triggers-bitbucket.yaml.

apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: bb-binding
  namespace: tekton-pipelines
spec:
  params:
    - name: gitrevision
      value: $(body.push.changes[0].new.name)
    - name: gitrepositoryurl
      value: $(body.repository.links.html.href)
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: bb-template
  namespace: tekton-pipelines
spec:
  params:
    - name: gitrevision
    - name: gitrepositoryurl
    - name: image
  resourcetemplates:
    - apiVersion: tekton.dev/v1beta1
      kind: PipelineRun
      metadata:
        generateName: bb-run-
      spec:
        serviceAccountName: kaniko-sa
        pipelineRef:
          name: build-push-pipeline
        params:
          - name: gitrepositoryurl
            value: $(tt.params.gitrepositoryurl)
          - name: gitrevision
            value: $(tt.params.gitrevision)
          - name: image
            value: $(tt.params.image)
        workspaces:
          - name: shared-data
            emptyDir: {}
---
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: bb-listener
  namespace: tekton-pipelines
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
    - name: on-bitbucket-push
      bindings:
        - ref: bb-binding
      template:
        ref: bb-template

kubectl apply -f triggers-bitbucket.yaml

Why:

Binding extracts branch + repo from Bitbucket webhook payload.

Template creates a PipelineRun that calls your pipeline.

EventListener exposes a service for Bitbucket to call.

Step 7 — Expose EventListener + Dashboard

Get ingress IP:
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

Say it’s 34.123.45.67. Use nip.io:

Dashboard: tekton.34-123-45-67.nip.io

EventListener: bb.34-123-45-67.nip.io

Ingress for EventListener:

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bb-listener-ing
  namespace: tekton-pipelines
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
    - host: bb.34-123-45-67.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: el-bb-listener
                port:
                  number: 8080

Ingress for Dashboard:

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard-ing
  namespace: tekton-pipelines
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
    - host: tekton.34-123-45-67.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: tekton-dashboard
                port:
                  number: 9097

kubectl apply -f bb-ingress.yaml
kubectl apply -f dashboard-ingress.yaml

Why: This makes Tekton UI available at one hostname and EventListener reachable by Bitbucket webhook at another.

Step 8 — Add webhook in Bitbucket

Go to Repo settings → Webhooks → Add webhook.

URL: http://bb.34-123-45-67.nip.io/

Trigger: Push

Why: This is the actual trigger connection — Bitbucket → Tekton.

# Create the tekton-triggers-rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-admin
rules:
  - apiGroups: ["triggers.tekton.dev"]
    resources:
      - eventlisteners
      - triggerbindings
      - triggertemplates
      - clustertriggerbindings
      - interceptors
      - clusterinterceptors    
      - triggers               
    verbs: ["get", "list", "watch", "create", "update", "delete"]
  - apiGroups: ["tekton.dev"]
    resources: ["pipelineruns", "pipelineresources", "taskruns"]
    verbs: ["get", "list", "watch", "create", "update", "delete"]
  - apiGroups: [""]
    resources: ["configmaps", "secrets", "serviceaccounts", "services", "pods", "events"]
    verbs: ["get", "list", "watch", "create", "update", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-admin-binding
subjects:
  - kind: ServiceAccount
    name: tekton-triggers-sa
    namespace: tekton-pipelines
roleRef:
  kind: ClusterRole
  name: tekton-triggers-admin
  apiGroup: rbac.authorization.k8s.io

This will make sure el-bb-listener po in teklon-pipelines namespace is running fine as it will through an error that permissions are missing for following
eventlisteners.triggers.tekton.dev is forbidden
triggerbindings.triggers.tekton.dev is forbidden
clustertriggerbindings.triggers.tekton.dev is forbidden
cannot list resource "clusterinterceptors" in API group "triggers.tekton.dev"
cannot list resource "triggers" in API group "triggers.tekton.dev"

# Option 1: Install tkn CLI 
# Download latest release (Linux AMD64)
curl -LO https://github.com/tektoncd/cli/releases/download/v0.36.0/tkn_0.36.0_Linux_x86_64.tar.gz

# Extract
tar xvzf tkn_0.36.0_Linux_x86_64.tar.gz

# Move binary to PATH
sudo mv tkn /usr/local/bin/

# Verify
tkn version

# authentication with bitbucket
create the token in bitbucket with read scope and copy paste the username and password

# Then create the secret in the cluster
vi bitbucket-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: bitbucket-token-secret
  namespace: tekton-pipelines
  annotations:
    tekton.dev/git-0: https://bitbucket.org
type: kubernetes.io/basic-auth
stringData:
  username: "atulghodmare1"   # <-- replace with your Bitbucket email/username
  password: "ATATT3xFfGF097irOg8mpB4zxXg7IivROw1KAywAtJpa3XIFNExJRotswd1n-LVHGCuMJdydb_qxGK4xsL7R8zFrGGzsYH2ueatjeiY2u0fdMzlwKCMX5DllzU_HN3TLrlgRazPrfhNasOPrrOLMfMTYH3GmxtGwHh1iC0FPMe4FDJsK6YZRaH4=5B2D81D8"   # <-- replace with your Bitbucket App password / API token

Apply the secret 

# Patch your ServiceAccount to use this secret which we have created above with secret field:
vi kaniko-sa-patch.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kaniko-sa
  namespace: tekton-pipelines
secrets:
  - name: bitbucket-token-secret

# create the test pipeline
vi test-pipeline.yaml
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: build-push-run-
  namespace: tekton-pipelines
spec:
  serviceAccountName: kaniko-sa
  pipelineRef:
    name: build-push-pipeline
  params:
    - name: gitrepositoryurl
      value: https://bitbucket.org/woodpeckernew/test.git   # ✅ remove username@ prefix
    - name: gitrevision
      value: main
    - name: image
      value: asia-south1-c-docker.pkg.dev/teklon/test/test-image:latest
  workspaces:
    - name: shared-data
      emptyDir: {}

tkn pipelinerun list -n tekton-pipelines
tkn pipelinerun logs -f build-push-run-bw7zd -n tekton-pipelines


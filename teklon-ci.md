Issues faced:
When the pipeline runs with task build and push , push was failing due to permission error as the pod was not assumming the SA which was assinged to it, it was assuming the default SA
Solution:
Cluster level workload identity(WI) was enabled but old nodepool was still running hence automatically only to the new nodepools WI will be enabled but not to the old nodepools hence updated manually the existing nodepool for WI by following command

check if cluster level workload identity is enabled or not
gcloud container clusters describe n7-playground-cluster \
    --project=nviz-playground \
    --zone=asia-south1-c \
    --format="value(workloadIdentityConfig.workloadPool)"

If not then enable using following command:
gcloud container clusters update n7-playground-cluster   --zone asia-south1-c   --workload-pool=nviz-playground.svc.id.goog


Then Check first if the respective nodepool have worload identity enabled or not:
gcloud container node-pools describe swap-memory-pool \
  --cluster=n7-playground-cluster \
  --zone=asia-south1-c \
  --format="yaml(config.workloadMetadataConfig)"

Enable the nodepool level WI using following command:
gcloud container node-pools update nodepoool-name \
  --cluster=cluster-name \
  --zone=asia-south1-c \
  --workload-metadata=GKE_METADATA

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
We can do it by ssh
ssh-keygen -t ed25519 -C "tekton-bot" -f ./tekton-ssh-key -N ""
ssh -i ./tekton-ssh-key git@bitbucket.org
ssh-keyscan bitbucket.org > known_hosts
mv ./tekton-ssh-key ~/.ssh/
mv ./tekton-ssh-key.pub ~/.ssh/
chmod 600 ~/.ssh/tekton-ssh-key
chmod 644 ~/.ssh/tekton-ssh-key.pub

# paste the public key in bitbucket ssh keys
check authentication success or not using following command
ssh -T git@bitbucket.org

create config file in .ssh loaction and add following :
Host bitbucket.org
  User git
  IdentityFile ~/.ssh/tekton-ssh-key
  
encode the private key and known host and config and paste in the secret.yaml
# Then create the secret in the cluster
vi bitbucket-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: git-credentials
  namespace: tekton-pipelines
data:
  tekton-ssh-key: LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNEcjM1U3NmSm43azFOL1hkYjJRa1U4OHl2anhaNkxSam0zemxNdE9VeU1zQUFBQUpDUU5BRXdrRFFCCk1BQUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDRHIzNVNzZkpuN2sxTi9YZGIyUWtVODh5dmp4WjZMUmptM3psTXRPVXlNc0EKQUFBRUFxRDFtY0EzbGRRM0hodXlwYWduMFFSOUNvWnlJY3pFdVdzMDlzaDFtZGZldmZsS3g4bWZ1VFUzOWQxdlpDUlR6egpLK1BGbm90R09iZk9VeTA1VEl5d0FBQUFDblJsYTNSdmJpMWliM1FCQWdNPQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K 
  known_hosts: fDF8b2lLVGk3TytocnVkOTk2VTQxWUZjTDlqQzBnPXxuLzNNMFVCQlZtV1RSRDAzNi9jclF3aTJqZ0E9IHNzaC1lZDI1NTE5IEFBQUFDM056YUMxbFpESTFOVEU1QUFBQUlJYXpFdTg5d2dRWjRicXMzZDYzUVNNellWYTBNdUoyZTJnS1RLcXUrVVVPCnwxfEJwWkFKRnZLUW43OGRpYWlDVllCZFhyRE9Kbz18dXlnMHBqRy81d1IraUh1Wm9wbjVsVDhzVDh3PSBlY2RzYS1zaGEyLW5pc3RwMjU2IEFBQUFFMlZqWkhOaExYTm9ZVEl0Ym1semRIQXlOVFlBQUFBSWJtbHpkSEF5TlRZQUFBQkJCUElRbXV6TUJ1S2RXZUY0K2Eyc2pTU3BCSzBpcWl0U1ErNUJNOUtocGV4dUd0MjBKcFRWTTd1NUJEWm5nbmNncnFETWJXZHhNV1dPR3RaOVVnYnFnWkU9CnwxfHpmU0dkU1RGSENGUFlkNE5VTDJFUzV0SVcwUT18cWQ0QUI1a3VnY2JvaFV1MzdDdDl1N1JOb1prPSBzc2gtcnNhIEFBQUFCM056YUMxeWMyRUFBQUFEQVFBQkFBQUJnUURRZUp6aHVwUnUwdTBjZGVnWklhOGU4NkVHMnFPQ3NJc0QxWHcweFNlaVBEbENyN2txOTdOTG1NYnBLVFg2RXNjMzBOdW9xRUVIQ3VjN3lXdHdwOGRJNzZFRUVCMVZxWTlRSnE2dmsrYXlTeWJvRDVRRjYxSS8xV2VUd3UrZGVDYmdLTUdiVWlqZVhodGZieFN4bTZKd0dyWHJoQmRvZlRzYktSVXNyTjFXb05nVWE4dXFOMVZ4NldBSncxSkhQaGdsRUdHSGVhNlFJQ3dKT0FyLzZtcnVpL29CN3BrYVdLSGozejdkMUlDNEtXTHRZNDdlbHZqYmFUbGtOMDRLYy81TEZFaXJvckdZVmJ0MTVrQVVscUdNNjVwazZaQnh0YU8zKzMwTFZsT1Jaa3hPaCtMS0wvQnZiWi9pUk5oSXRMcU55aWVvUWovdWgvN0l2NHV5SC9jVi8wYjRXRFNkM0RwdGlnV3E4NGxKdWJiOXQvRG5abHJKYXp4eURDdWxUbUtkT1I3dnM5Z01Ubyt1b0lyUFNiOFNjVHR2dzY1K29kS0FsQmo1OWRoblZwOXpkN1FVb2pPcFhsTDYyQXc1NlU0b08rRkFMdWV2dk1qaVdlYXZLaEpxbFI3aTVuOXNyWWNyTlY3dHRtRHc3a2YvOTdQNXphdUloeGNqWCt4SHY0TT0K  
  config: SG9zdCBiaXRidWNrZXQub3JnCiAgVXNlciBnaXQKICBJZGVudGl0eUZpbGUgfi8uc3NoL3Rla3Rvbi1zc2gta2V5

Apply the secret 
# Stage 1 clone the repo and read the read me file from repo
We need 3 files pipeline, pipelinerun, tasks[ clone & readme ]

tkn hub install task git-clone -n test
OR
kubectl apply -f \
https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.6/git-clone.yaml -n test # This will install latest version dont run it as it is not working as expected

create task readme.yaml
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

create pipeline.yaml
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

Create pipelinerun.yaml
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

Apply the show-readme Task:
kubectl apply -f readme.yaml

Apply the Pipeline:
kubectl apply -f pipeline.yaml

Create the PipelineRun:
kubectl create -f pipelinerun.yaml

This creates a PipelineRun with a unique name each time:
pipelinerun.tekton.dev/clone-read-run-4kgjr created

Use the PipelineRun name from the output of the previous step to monitor the Pipeline execution:
tkn pipelinerun list -n tekton-pipelines

Above steps will do clone the private repo and then read the readme file from the repo means private clone success



# How to clone and build the application and then push the image to artifact registry

First we need to create the authentication with artifact registry, follow following steps for gke for other cloud follow steps from docs:
Enable the Artifact Registry API:
To check if it is already enabled : gcloud services list --filter="name:artifactregistry.googleapis.com"
To enable the service run cmd: gcloud services enable artifactregistry.googleapis.com

Create a Docker repository to push the image to:
gcloud artifacts repositories create <repository-name> \
  --repository-format=docker \
  --location=us-central1 --description="Docker repository"

Create a Kubernetes Service Account:
kubectl create serviceaccount tekton-sa -n test

gcloud iam service-accounts create tekton-sa

gcloud artifacts repositories add-iam-policy-binding zendesk \
  --location asia-south1 \
  --member=serviceAccount:tekton-sa@nviz-playground.iam.gserviceaccount.com \
  --role=roles/artifactregistry.reader \
  --role=roles/artifactregistry.writer

kubectl annotate serviceaccount \
tekton-sa \
iam.gke.io/gcp-service-account=tekton-sa@nviz-playground.iam.gserviceaccount.com \
-n test

gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:nviz-playground.svc.id.goog[test/tekton-sa]" \
  tekton-sa@nviz-playground.iam.gserviceaccount.com

This creates two service accounts, an IAM service account and a Kubernetes service account, and “links” them. Workload Identity allows workloads in your GKE cluster to impersonate IAM service accounts to access Google Cloud services.

# create pipeline.yaml, pipelinerun.yaml and install clone and build task in test namespace:
Create secret for cloning the repo as did above
check if the secrets exist
kubect get secret -n test

Check if clone task is already installed in the test namespace
tkn tasks list -n test
If not then install

Create kaniko-build task
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

  Create pipeline

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

Create pipelinerun

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

k apply -f kaniko-build.yaml
k apply -f pipeline.yaml
k create -f pipelinerun.yaml
Then check the pipelinerun logs
tkn pipelinern list -n test
tkn pipelinerun logs name -n test

# Now we want to automate it with trigger
create role, rolebinding, clusterrole, clusterrolebindings
vi tekton-sa-role.yaml
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
k apply -f tekton-sa-role.yaml

vi tekton-sa-rolebinding.yaml
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
k apply -f tekton-sa-rolebinding.yaml

vi cluster-role-rolebinding.yaml
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
k apply -f cluster-role-rolebinding.yaml


Create following files
vi clustertriggerbinding.yaml
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

vi trigger-template.yaml
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
            value: asia-south1-docker.pkg.dev/tekton4/tekton:$(tt.params.commit_sha)
vi trigger.yaml
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
          value: "body.push.changes[0].new.name == 'main'"

vi event-listner.yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: bitbucket-listener
  namespace: test
spec:
  serviceAccountName: tekton-sa
  triggers:
    - triggerRef: bitbucket-push-trigger

Apply all the files in order:
kubectl apply -f clustertriggerbinding.yaml        
kubectl apply -f trigger-template.yaml
kubectl apply -f trigger.yaml
kubectl apply -f event-listner.yaml

Verify if the objects are applied and deployed
kubectl get clustertriggerbindings
kubectl get triggertemplate -n test
kubectl get trigger -n test
kubectl get eventlistener -n test

# create ingress configuration 

Then create the ingress for bitbucket webhook url which should be publically accessible
vi bitbucket-listner-ingress.yaml
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
k apply -f bitbucket-listner-ingress.yaml
Check the ing: k get ing -n test
If new load balancer ip arrives the edit the ing and add that in the host

# create the webhook for bitbucket
Now go the bitbucket repo and in the repo setting add the webhook
name: Tekton Trigger
URL: http://bitbucket-listener.35.244.2.22.nip.io
Triggers: select Repository push (or whatever event your TriggerTemplate expects)







































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

tkn pipelinerun logs -f build-push-run-bw7zd -n tekton-pipelines

After this we can check the pods in the tekton-pipelines namespace

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

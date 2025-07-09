Kubeip deployment using taint:

Apply taint to the nodepool:
Effect: NO_SCHEDULE 
Key: kubeip.com/not-ready
Value: true

# Create the static public ip using following command:
gcloud compute addresses create kubeip-node-1   --region=asia-south1
gcloud compute addresses list --filter="name=kubeip-node-1"

# Now we need to label our Reserved Static IP Address (kubeip-node-1):

gcloud beta compute addresses update kubeip-node-1 \
  --region asia-south1 \
  --update-labels=kubeip=reserved,environment=dev

Verify IP labels:
gcloud compute addresses describe kubeip-node-1 --region asia-south1 --format=json 

We should see an output like: "labels": { "environment": "demo", "kubeip": "reserved" }.


# check if the worklad identity is set for the cluster, to check run following command:
gcloud container clusters describe n7-playground-cluster \
    --region=asia-south1-c \
    --project=nviz-playground \
    --flatten 'workloadIdentityConfig'

# If not set then Enable Workload Identity on Your GKE Cluster (Cluster Level):

gcloud container clusters update n7-playground-cluster \
  --zone asia-south1-c \
  --workload-pool=nviz-playground.svc.id.goog   # in workload pool project id will come

# Enable GKE Metadata Server on Node Pool:
gcloud container node-pools update kubeip-pool \
  --cluster n7-playground-cluster \
  --zone asia-south1-c \
  --workload-metadata=GKE_METADATA

# Create a Dedicated GCP Service Account for KubeIP:
gcloud iam service-accounts create kubeip-gcp-sa \
  --display-name "KubeIP GCP Service Account for Workload Identity" \
  --project nviz-playground
KUBEIP_GCP_SA_EMAIL="kubeip-gcp-sa@nviz-playground.iam.gserviceaccount.com"

# Create a Custom IAM Role 
create a file by name kubeip-custom-role.yaml and add following permissions:

title: "KubeIP Role"
description: "KubeIP required permissions for GCP API calls"
stage: "GA"
includedPermissions:
  - compute.instances.addAccessConfig
  - compute.instances.deleteAccessConfig
  - compute.instances.get
  - compute.addresses.get
  - compute.addresses.list
  - compute.addresses.use
  - compute.zoneOperations.get
  - compute.zoneOperations.list
  - compute.subnetworks.useExternalIp
  - compute.projects.get

Then run following command:
gcloud iam roles create kubeip_role --project nviz-playground \
  --file=kubeip-custom-role.yaml || \
gcloud iam roles update kubeip_role --project nviz-playground \
  --file=kubeip-custom-role.yaml

# Bind the Custom Role to Your New GCP Service Account:

gcloud projects add-iam-policy-binding nviz-playground \
  --member="serviceAccount:$KUBEIP_GCP_SA_EMAIL" \
  --role="projects/nviz-playground/roles/kubeip_role"

# Create Kubernetes Service Account and Bind to GCP SA via Workload Identity:

create file by name kubeip-workload-identity-rbac.yaml and add following:

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kubeip-service-account
  namespace: kube-system
  annotations:
        # This annotation links the K8s SA to the GCP SA for Workload Identity
    iam.gke.io/gcp-service-account: kubeip-gcp-sa@nviz-playground.iam.gserviceaccount.com
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kubeip-cluster-role
rules:
  - apiGroups: [ "" ] # Core API group for nodes
    resources: [ "nodes" ]
    verbs: [ "get" ] # KubeIP needs to get node info
  - apiGroups: [ "coordination.k8s.io" ] 
    resources: [ "leases" ]
    verbs: [ "create", "get", "delete" ] 
  - apiGroups: [ "" ]
    resources: [ "nodes" ]
    verbs: [ "get", "patch" ]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeip-cluster-role-binding
subjects:
  - kind: ServiceAccount
    name: kubeip-service-account 
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: kubeip-cluster-role # Refers to the ClusterRole defined above
  apiGroup: rbac.authorization.k8s.io

Then apply the file: kubectl apply -f kubeip-workload-identity-rbac.yaml

# Bind Workload Identity User Role to the GCP Service Account: 

gcloud iam service-accounts add-iam-policy-binding \
  $KUBEIP_GCP_SA_EMAIL \
  --member="serviceAccount:nviz-playground.svc.id.goog[kube-system/kubeip-service-account]" \
  --role="roles/iam.workloadIdentityUser"

# GKE Node Pool Configuration (Labeling)

gcloud container node-pools update kubeip-pool \
  --cluster test \
  --zone asia-south1-c \
  --node-labels=nodegroup=public,kubeip=use

# Verify New Node Labels:

kubectl get nodes gke-test-kubeip-pool-fe8d653c-sm5w -o yaml | grep -E "nodegroup|kubeip"

we should see output similar to:

nodegroup: "public"
kubeip: "use"

# Deploy KubeIP DaemonSet:

create file by name kubeip-ds.yaml add following:

---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kubeip
  namespace: kube-system
  labels:
    app: kubeip
spec:
  selector:
    matchLabels:
      app: kubeip
  template:
    metadata:
      labels:
        app: kubeip
    spec:
      serviceAccountName: kubeip-service-account
      terminationGracePeriodSeconds: 30
      priorityClassName: system-node-critical
      nodeSelector:
        nodegroup: "public"
        kubeip: "use"
      tolerations:
        - key: kubeip.com/not-ready
          operator: Exists
          effect: NoSchedule
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        runAsGroup: 1001
        fsGroup: 1001
      containers:
        - name: kubeip
          image: doitintl/kubeip-agent:2.2.0
          imagePullPolicy: Always
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: FILTER
              value: "labels.kubeip=reserved;labels.environment=dev"
            - name: LOG_LEVEL
              value: debug
            - name: LOG_JSON
              value: "true"
            - name: TAINT_KEY
              value: "kubeip.com/not-ready" 
          securityContext:
            privileged: false
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: true
          resources:
            requests:
              cpu: "100m"

kubectl apply -f kubeip-ds.yaml

kubectl get daemonset kubeip-agent -n kube-system

kubectl get pods -n kube-system -l app=kubeip -o wide 

kubectl logs podname -n kubesystem > In output we should see following msg

"msg":"Successfully assigned static public IP address to node" or "msg":"Successfully assigned IP..."

# Verify External IP Assignment on the Node:

kubectl get nodes -o wide

$ Now if want to attach 2nd static public ip to the 2nd node 
#Create a second static public IP: kubeip-node-2

gcloud compute addresses create kubeip-node-2 --region=asia-south1 --quiet

# Verify the ip:
gcloud compute addresses list --filter="name=kubeip-node-2"

# Label the Second Static IP:
gcloud beta compute addresses update kubeip-node-2 \
  --region asia-south1 \
  --update-labels=kubeip=reserved,environment=dev

Verify the label:
gcloud compute addresses describe kubeip-node-2 --region asia-south1 --format=json 

# Scale Your Node Pool to 2 Nodes:

gcloud container clusters resize test \
  --node-pool kubeip-pool \
  --num-nodes 2 \
  --zone asia-south1-a

# After this the kubeip-agent pod will get deployed and it will assign the 2nd public ip as present.

gcloud compute addresses delete kubeip-node-1 \
  --region=asia-south1


# TO find out which type of cluster autoscaler present
gcloud container clusters describe n7-playground-cluster   --zone asia-south1-c   --format="yaml" | yq '.autoscaling'

# To update the autoscaling profile:
gcloud container clusters update kubeip-cluster \
  --zone asia-south1-c \
  --autoscaling-profile balanced

# If we are using taint then we have to follow following steps:

k edit deploy kube-dns  -n kube-system

then add the following toleration

tolerations:
      - key: "kubeip.com/not-ready"
        operator: "Exists"
        effect: "NoSchedule" 

# To login into the node and check the logs of kubeip use following commands:
gcloud compute ssh gke-kubeip-cluster-default-pool-2356a61a-jqs7 \
  --zone asia-south1-a

sudo crictl ps -a | grep kubeip

sudo crictl logs a4398ad5518a7


# KubeIP Deployment using Taint

This guide provides step-by-step instructions to deploy **KubeIP** on a GKE cluster using **taints and tolerations**.

---

## 1. Configure Autoscaling

If using autoscaling in the nodes, the following step is a must.

Find out which type of cluster autoscaler is present:

```bash
gcloud container clusters describe n7-playground-cluster   --zone asia-south1-c   --format="yaml" | yq '.autoscaling'
```

Update the autoscaling profile to `balanced` (as `cluster-optimised` will not work):

```bash
gcloud container clusters update kubeip-cluster   --zone asia-south1-c   --autoscaling-profile balanced
```

---

## 2. Create and Label Static Public IPs

Create the first static public IP:

```bash
gcloud compute addresses create kubeip-node-1 --region=asia-south1
gcloud compute addresses list --filter="name=kubeip-node-1"
```

Label the reserved static IP:

```bash
gcloud beta compute addresses update kubeip-node-1   --region asia-south1   --update-labels=kubeip=reserved,environment=dev
```

Verify labels:

```bash
gcloud compute addresses describe kubeip-node-1   --region asia-south1   --format=json
```

> You should see an output like:  
> `"labels": { "environment": "demo", "kubeip": "reserved" }`

### Add a Second Static IP

```bash
gcloud compute addresses create kubeip-node-2 --region asia-south1 --quiet
gcloud compute addresses list --filter="name=kubeip-node-2"
gcloud beta compute addresses update kubeip-node-2   --region asia-south1   --update-labels=kubeip=reserved,environment=dev
gcloud compute addresses describe kubeip-node-2   --region asia-south1   --format=json
```

---

## 3. Enable Workload Identity

Check if Workload Identity is enabled:

```bash
gcloud container clusters describe n7-playground-cluster   --region=asia-south1-c   --project=nviz-playground   --flatten 'workloadIdentityConfig'
```

If not set, enable it:

```bash
gcloud container clusters update n7-playground-cluster   --zone asia-south1-c   --workload-pool=nviz-playground.svc.id.goog
```

Enable GKE Metadata Server on the node pool:

```bash
gcloud container node-pools update kubeip-pool   --cluster n7-playground-cluster   --zone asia-south1-c   --workload-metadata=GKE_METADATA
```

---

## 4. Create GCP Service Account

```bash
gcloud iam service-accounts create kubeip-gcp-sa   --display-name "KubeIP GCP Service Account for Workload Identity"   --project nviz-playground

KUBEIP_GCP_SA_EMAIL="kubeip-gcp-sa@nviz-playground.iam.gserviceaccount.com"
```

---

## 5. Create Custom IAM Role

Create a file named `kubeip-custom-role.yaml`:

```yaml
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
```

Create or update the role:

```bash
gcloud iam roles create kubeip_role --project nviz-playground   --file=kubeip-custom-role.yaml || gcloud iam roles update kubeip_role --project nviz-playground   --file=kubeip-custom-role.yaml
```

Bind the role:

```bash
gcloud projects add-iam-policy-binding nviz-playground   --member="serviceAccount:$KUBEIP_GCP_SA_EMAIL"   --role="projects/nviz-playground/roles/kubeip_role"
```

---

## 6. Create Kubernetes Service Account and RBAC

Create a file named `kubeip-workload-identity-rbac.yaml`:

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kubeip-service-account
  namespace: kube-system
  annotations:
    iam.gke.io/gcp-service-account: kubeip-gcp-sa@nviz-playground.iam.gserviceaccount.com
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kubeip-cluster-role
rules:
  - apiGroups: [ "" ]
    resources: [ "nodes" ]
    verbs: [ "get" ]
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
  name: kubeip-cluster-role
  apiGroup: rbac.authorization.k8s.io
```

Apply it:

```bash
kubectl apply -f kubeip-workload-identity-rbac.yaml
```

Bind Workload Identity:

```bash
gcloud iam service-accounts add-iam-policy-binding   $KUBEIP_GCP_SA_EMAIL   --member="serviceAccount:nviz-playground.svc.id.goog[kube-system/kubeip-service-account]"   --role="roles/iam.workloadIdentityUser"
```

---

## 7. Configure Node Pool

Add node labels:

```bash
gcloud container node-pools update kubeip-pool   --cluster test   --zone asia-south1-c   --node-labels=nodegroup=public,kubeip=use
```

Verify:

```bash
kubectl get nodes gke-test-kubeip-pool-fe8d653c-sm5w -o yaml | grep -E "nodegroup|kubeip"
```

Expected output:

```yaml
nodegroup: "public"
kubeip: "use"
```

---

## 8. Apply Node Taint

Effect: `NO_SCHEDULE`  
Key: `kubeip.com/not-ready`  
Value: `true`

Update toleration in konnectivity agent:

```bash
kubectl edit deploy konnectivity-agent -n kube-system
```

Add toleration:

```yaml
- key: "kubeip.com/not-ready"
  operator: "Exists"
  effect: "NoSchedule"
```

---

## 9. Deploy KubeIP DaemonSet

Create `kubeip-ds.yaml`:

```yaml
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
              drop: [ "ALL" ]
            readOnlyRootFilesystem: true
          resources:
            requests:
              cpu: "100m"
```

Apply it:

```bash
kubectl apply -f kubeip-ds.yaml
kubectl get daemonset kubeip -n kube-system
kubectl get pods -n kube-system -l app=kubeip -o wide
kubectl logs <pod-name> -n kube-system
```

> Expected log message:  
> `"Successfully assigned static public IP address to node"`

---

## 10. Verify IP Assignment

```bash
kubectl get nodes -o wide
```

Scale the node pool to 2 nodes:

```bash
gcloud container clusters resize test   --node-pool kubeip-pool   --num-nodes 2   --zone asia-south1-a
```

The second node should be assigned the second static public IP.

---

## 11. Cleanup

Delete a static IP:

```bash
gcloud compute addresses delete kubeip-node-1 --region=asia-south1
```

---

## 12. Debugging

Login to node and check logs:

```bash
gcloud compute ssh gke-kubeip-cluster-default-pool-2356a61a-jqs7   --zone asia-south1-a

sudo crictl ps -a | grep kubeip
sudo crictl logs <container-id>
```

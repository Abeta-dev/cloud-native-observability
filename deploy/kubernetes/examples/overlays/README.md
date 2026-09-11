# Cloud Provider Overlays (Examples & Templates)

> [!NOTE]
> **TEMPLATE ONLY - NOT WIRED IN BASE**
>
> The manifests in this directory are example overlays for specific managed cloud Kubernetes environments (AWS EKS, GCP GKE). They are **not** referenced by default in the base GitOps manifests or Helm values to prevent startup failures caused by unwired cloud infrastructure (such as missing cloud IAM roles, CSI storage drivers, or object storage buckets).

---

## 📋 Available Overlays

| Overlay | Target Cloud | StorageClass | Identity Mechanism | Object Storage Secret |
|:---|:---|:---|:---|:---|
| [`values-eks.yaml`](values-eks.yaml) | AWS EKS | `gp3` (AWS EBS CSI) | AWS IRSA (`eks.amazonaws.com/role-arn`) | `thanos-objstore-secret` (S3) |
| [`values-gke.yaml`](values-gke.yaml) | GCP GKE | `standard-rwo` (GKE PD) | Workload Identity (`iam.gke.io/gcp-service-account`) | `thanos-gcs-secret` (GCS) |

---

## 🛠️ Prerequisites & Setup

### 1. Storage Drivers
- **AWS EKS**: Ensure the `aws-ebs-csi-driver` EKS add-on is installed so persistent volume claims using `gp3` can be provisioned.
- **GCP GKE**: The `standard-rwo` storage class is available by default on GKE standard clusters.

### 2. IAM & Workload Identity
Before applying either overlay, create the appropriate cloud IAM role and bind it to the Kubernetes service account:

- **AWS IRSA**:
  1. Create an IAM role with S3 read/write permissions to your Thanos S3 bucket.
  2. Add trust policy for the EKS cluster OIDC provider.
  3. Replace the placeholder ARN `arn:aws:iam::123456789012:role/prometheus-s3-backup-role` with your actual role ARN.
- **GCP Workload Identity**:
  1. Create a Google Service Account (GSA) with `roles/storage.objectAdmin` on your Thanos GCS bucket.
  2. Bind the GSA to the Kubernetes Service Account (KSA) in the `monitoring` namespace:
     ```bash
     gcloud iam service-accounts add-iam-policy-binding \
       prometheus-sa@YOUR_PROJECT.iam.gserviceaccount.com \
       --role roles/iam.workloadIdentityUser \
       --member "serviceAccount:YOUR_PROJECT.svc.id.goog[monitoring/kube-prometheus-stack-prometheus]"
     ```
  3. Replace the placeholder `prometheus-sa@my-gcp-project.iam.gserviceaccount.com` in `values-gke.yaml`.

### 3. Thanos Object Storage Secret
Deploy the Thanos configuration secret in the `monitoring` namespace using the template provided at [`deploy/kubernetes/secrets/thanos-objstore-secret.yaml.example`](../../secrets/thanos-objstore-secret.yaml.example):

```bash
# S3 / AWS:
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: thanos-objstore-secret
  namespace: monitoring
type: Opaque
stringData:
  thanos.yaml: |
    type: S3
    config:
      bucket: cno-thanos-metrics-prod
      endpoint: s3.us-east-1.amazonaws.com
      insecure: false
EOF

# GCS / GCP:
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: thanos-gcs-secret
  namespace: monitoring
type: Opaque
stringData:
  thanos.yaml: |
    type: GCS
    config:
      bucket: cno-thanos-metrics-prod
EOF
```

---

## 🚀 Deployment Instructions

Merge the overlay values file on top of the base values with Helm:

```bash
# AWS EKS
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml \
  -f deploy/kubernetes/examples/overlays/values-eks.yaml

# GCP GKE
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml \
  -f deploy/kubernetes/examples/overlays/values-gke.yaml
```

#!/usr/bin/env bash
# Full deploy. Run infra from anywhere with gcloud access; run the kubectl steps
# from the jumpbox (via IAP), since the control plane is private.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== 1/4 Infrastructure =="
cd "$here/terraform"
terraform init
terraform apply -auto-approve

AR=$(terraform output -raw artifact_registry)
BUCKET=$(terraform output -raw weights_bucket)
WEIGHTS_SA=$(terraform output -raw weights_reader_sa)
CLUSTER=$(terraform output -raw cluster_name)
LOCATION=$(terraform output -raw cluster_location)

echo "== 2/4 Seed images + weights into the private registry/bucket =="
echo "Run, from a host with internet + project access:"
echo "  AR=$AR BUCKET=$BUCKET MODEL_LOCAL_DIR=./model $here/scripts/seed-artifacts.sh"
read -r -p "Press enter once seeding is done..."

echo "== 3/4 Cluster credentials (private endpoint — run on the jumpbox) =="
gcloud container clusters get-credentials "$CLUSTER" --location "$LOCATION" --internal-ip

echo "== 4/4 Workloads =="
# Substitute deploy-time values into the manifests.
tmp=$(mktemp -d)
cp -r "$here/kubernetes" "$tmp/"
grep -rl -e '<BUCKET_NAME>' -e '<WEIGHTS_SA_EMAIL>' -e 'REGION-docker.pkg.dev/PROJECT/privllm-images' "$tmp/kubernetes" | while read -r f; do
  sed -i.bak \
    -e "s|<BUCKET_NAME>|$BUCKET|g" \
    -e "s|<WEIGHTS_SA_EMAIL>|$WEIGHTS_SA|g" \
    -e "s|REGION-docker.pkg.dev/PROJECT/privllm-images|$AR|g" "$f"
  rm -f "$f.bak"
done

kubectl apply -f "$tmp/kubernetes/base/00-namespaces.yaml"
kubectl apply -f "$tmp/kubernetes/base/10-network-policies.yaml"
kubectl apply -f "$tmp/kubernetes/base/20-model-weights.yaml"
kubectl apply -f "$tmp/kubernetes/base/30-vllm.yaml"
kubectl apply -f "$tmp/kubernetes/gateway/litellm.yaml"
kubectl apply -f "$tmp/kubernetes/observability/podmonitoring.yaml"
rm -rf "$tmp"

echo "Waiting for the private LLM endpoint IP..."
kubectl -n gateway get svc litellm -w

# Dashboards: the Cloud Monitoring dashboard is created by Terraform. For Grafana,
# import kubernetes/observability/grafana-dashboard-vllm.json against a GMP source.

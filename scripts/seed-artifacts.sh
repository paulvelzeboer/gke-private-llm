#!/usr/bin/env bash
# One-time controlled ingress: copy the images and model weights the cluster
# needs INTO private Artifact Registry and the private GCS bucket. Run from an
# operator machine that has internet AND can reach the project (e.g. the jumpbox
# over IAP, or any authenticated host). After this, the cluster needs no internet.
#
# This is the single, auditable door through which anything enters the air-gap.
set -euo pipefail

: "${AR:?set AR to the registry path, e.g. europe-west4-docker.pkg.dev/PROJECT/privllm-images}"
: "${BUCKET:?set BUCKET to the weights bucket name (no gs:// prefix)}"
: "${MODEL_LOCAL_DIR:?set MODEL_LOCAL_DIR to the downloaded weights directory}"

gcloud auth configure-docker "${AR%%/*}" --quiet

# ---- 1. Images: copy from public registries into Artifact Registry --------
# crane needs no docker daemon. Install: go install github.com/google/go-containerregistry/cmd/crane@latest
images=(
  "docker.io/vllm/vllm-openai:v0.6.3|vllm/vllm-openai:v0.6.3"
  "ghcr.io/berriai/litellm:main-stable|berriai/litellm:main-stable"
)
for entry in "${images[@]}"; do
  src="${entry%%|*}"; dst="${entry##*|}"
  echo ">> copying $src -> $AR/$dst"
  crane copy "$src" "$AR/$dst"
done

# ---- 2. Weights: upload the model directory to the private bucket ---------
# Download once (e.g. huggingface-cli download <repo> --local-dir MODEL_LOCAL_DIR),
# then push under current/ (the vLLM mount uses only-dir=current).
echo ">> uploading weights from $MODEL_LOCAL_DIR to gs://$BUCKET/current/"
gcloud storage cp --recursive "$MODEL_LOCAL_DIR/*" "gs://$BUCKET/current/"

echo "Seed complete. The cluster can now run fully air-gapped."

# Running a model

## How serving works here

Because the cluster is air-gapped, a model is never downloaded at runtime:

```
download once (operator, online) ──▶ upload to private GCS (gs://<bucket>/current/)
          │                                      │
          ▼                                      ▼
   seed-artifacts.sh            GCS-FUSE mounts current/ read-only at /models
                                                 │
                                                 ▼
                              vLLM serves it as model "private-llm" on :8000
```

Weights live under `current/` in the private bucket; the GCS-FUSE CSI mount uses `only-dir=current`
so that prefix is the mount root (`/models`). vLLM always advertises the model under the stable
name **`private-llm`**, so clients never change when you swap the underlying weights.

vLLM runs with `HF_HUB_OFFLINE=1`, so it fails fast rather than ever reaching HuggingFace.

## Example: Llama 3.1 8B Instruct (the default)

`meta-llama/Llama-3.1-8B-Instruct` is the most widely used open instruct model and fits comfortably
on one A100 80 GB. It is what `kubernetes/base/30-vllm.yaml` is configured for.

> Llama 3.1 is **license-gated** on HuggingFace: accept the license once, then authenticate
> `huggingface-cli`. For an ungated alternative with identical steps, use
> `Qwen/Qwen2.5-7B-Instruct` (set `--tool-call-parser=hermes` instead of `llama3_json`).

### 1. Download the weights once (on an online host)

```bash
pip install -U "huggingface_hub[cli]"
huggingface-cli login                       # token that accepted the license
mkdir -p ./model
huggingface-cli download meta-llama/Llama-3.1-8B-Instruct \
  --local-dir ./model --exclude "original/*"
```

### 2. Seed it into the air-gap

```bash
AR=$(terraform -chdir=terraform output -raw artifact_registry)
BUCKET=$(terraform -chdir=terraform output -raw weights_bucket)
AR="$AR" BUCKET="$BUCKET" MODEL_LOCAL_DIR=./model ./scripts/seed-artifacts.sh
```

Uploads `./model/*` to `gs://<bucket>/current/` and copies the vLLM/LiteLLM images into Artifact
Registry.

### 3. Deploy / restart (from the jumpbox)

```bash
kubectl apply -f kubernetes/base/30-vllm.yaml
kubectl -n llm rollout status deploy/vllm --timeout=15m   # first load streams weights from GCS
```

Matching tool-calling flags for Llama 3.x are already set:

```yaml
- --model=/models
- --served-model-name=private-llm
- --tensor-parallel-size=1          # = GPU count per node
- --max-model-len=16384
- --enable-auto-tool-choice
- --tool-call-parser=llama3_json
```

### 4. Verify (from the jumpbox)

```bash
LLM_KEY=<virtual-key> ./scripts/connect-cli.sh
```

## Swapping or sizing a model

| Want | Change |
|---|---|
| A different model | Re-seed new weights to `gs://<bucket>/current/`, then `kubectl -n llm rollout restart deploy/vllm`. Keep the served name `private-llm`. |
| A bigger model (e.g. Llama 3.1 70B) | Use a multi-GPU machine type (`a2-ultragpu-2g/4g/8g`), set `--tensor-parallel-size` to the GPU count, and update `gpu_machine_type`. |
| A non-Llama family | Set `--tool-call-parser` to that family's parser (`hermes` for Qwen, `mistral` for Mistral). Mismatched parser = broken tool calls. |
| Multiple models | Add `model_list` entries in `kubernetes/gateway/litellm.yaml`, each pointing at its own vLLM Service. |

## Why tool calling is on

Copilot CLI and agentic clients (aider, Continue, Cline) require tool/function calling and
streaming. `--enable-auto-tool-choice` + the correct `--tool-call-parser` enable it; without a
matching parser the endpoint still answers plain chat but agent features silently fail. See
[connect-copilot-cli.md](connect-copilot-cli.md).

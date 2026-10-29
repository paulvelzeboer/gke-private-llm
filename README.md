# Private, air-gapped LLM on GKE

A fully controlled self-hosted LLM platform on Google Kubernetes Engine. Open-weight models run on
GPU nodes behind a private network with **no internet egress**, every request is authenticated and
audited, and nothing — control plane, inference API, registry, or bucket — is exposed to the
internet. Clients talk to it through an OpenAI-compatible endpoint on a private IP.

> This is the Google Cloud counterpart of the Azure build (`aks-private-llm`). Same architecture,
> GCP-native primitives.

```
                       ┌─────────────────── GCP VPC 10.42.0.0/20 (no Cloud NAT, private nodes) ───────────────────┐
                       │                                                                                          │
 operator ──IAP SSH──▶ │  jumpbox (no ext IP) ──kubectl / curl──▶ [internal LB :4000]                             │
 (OS Login)            │                                                  │                                       │
                       │  namespace: gateway                       ┌──────▼───────┐  auth (virtual keys)          │
                       │                                           │   LiteLLM    │  + FULL audit ──▶ stdout       │
                       │                                           └──────┬───────┘                 │             │
                       │  namespace: llm   Spot GPU pool   ┌──────────────▼┐ (NetworkPolicy)        │             │
                       │  (default-deny egress)            │  vLLM :8000   │◀── weights (GCS FUSE)  │             │
                       │                                   └───────────────┘                        ▼             │
                       │  images ◀── Artifact Registry ──┐                              Cloud Logging + GMP       │
                       │  weights ◀── GCS ───────────────┘  (via Private Google Access)      │                   │
                       │                                                                      ▼                   │
                       │   all egress ─▶ [deny-all firewall + flow logs] ─▶ only restricted.googleapis.com VIP    │
                       └──────────────────────────────────────────────────────────────────────────────────────┘
                                              everything else: no route (no NAT) AND denied + logged
```

## What "controlled" means here

| Requirement | How it is enforced |
|---|---|
| External data blocked | Private nodes + **no Cloud NAT** = no internet route; an explicit **deny-all egress** firewall rule + Dataplane V2 `default-deny` NetworkPolicies. Google APIs only via the restricted VIP. |
| Air-gapped artifacts | Artifact Registry + GCS are IAM-private, reached over Private Google Access. Images/weights seeded **once** (`seed-artifacts.sh`); vLLM runs `HF_HUB_OFFLINE=1`. |
| Monitored | VPC flow logs + firewall logs + LiteLLM per-request audit → Cloud Logging (queries in `kubernetes/observability/audit-queries.md`). Metrics via Managed Prometheus → a Cloud Monitoring dashboard (`terraform/monitoring.tf`). |
| Controlled access | Private control-plane endpoint, master authorized networks, Workload Identity, least-privilege node SA. LLM API is an **internal** LB reachable only inside the VPC via an IAP jumpbox. LiteLLM issues per-client virtual keys with budgets. |
| CLI access | OpenAI-compatible endpoint → **GitHub Copilot CLI** (BYOK), `llm`, aider, Continue, Cline, or the OpenAI SDK. See `docs/connect-copilot-cli.md`. |

## Layout

```
terraform/   VPC + egress lockdown + Private Google Access, private GKE +
             Spot GPU pool, Artifact Registry + GCS, IAP jumpbox, GMP +
             Cloud Monitoring dashboard, least-privilege IAM
kubernetes/
  base/      namespaces, NetworkPolicies, GCS-FUSE weights, vLLM
  gateway/   LiteLLM auth + audit proxy on an internal load balancer
  observability/  PodMonitoring (GMP), Cloud Logging queries, Grafana dashboard
scripts/     seed-artifacts.sh (one-time ingress), deploy.sh, connect-cli.sh
docs/        architecture.md, running-a-model.md, connect-copilot-cli.md, costs.md
```

## Deploy

Prereqs: a GCP project with GPU quota (`NVIDIA_A100_80GB` in the region), `gcloud`, `terraform`,
`kubectl`, `crane`, and a one-time download of your model weights.

```bash
# 1. Infra (needs project owner/editor-ish rights)
cd terraform
terraform init
terraform apply -var project_id=<PROJECT> -var 'iap_members=["user:you@example.com"]'

# 2. Seed the air-gap (from a host with internet + project access)
AR=$(terraform output -raw artifact_registry) BUCKET=$(terraform output -raw weights_bucket) \
  MODEL_LOCAL_DIR=./model ../scripts/seed-artifacts.sh

# 3+4. Workloads (from the jumpbox, over IAP — the control plane is private)
gcloud compute ssh vm-privllm-jump --tunnel-through-iap
../scripts/deploy.sh

# Talk to it
LLM_KEY=<virtual-key> ../scripts/connect-cli.sh
```

See `docs/running-a-model.md` for the Llama 3.1 8B walkthrough.

## Cost

The GPU dominates, so it runs on **Spot by default** (`use_spot_gpu = true`) — typically **~60–90%
cheaper** than on-demand, with the tradeoff that GCP can preempt the node (~30s notice) and the
model pod restarts. `gpu_min_count = 0` also lets the pool scale to zero.

Rough europe-west4 monthly estimates (full breakdown in [`docs/costs.md`](docs/costs.md)):

| Scenario | ~ Monthly |
|---|---|
| On-demand GPU, 24/7 | ~$3,200–4,100 |
| **Spot GPU, 24/7 (default)** | **~$1,300–2,000** |
| Spot GPU, business hours + scale-to-zero | ~$550–790 |

Unlike the Azure build, the fixed perimeter here is only **~$350–410/mo** — GCP's air-gap uses
free/near-free primitives (no managed firewall or bastion charge), so the GPU is nearly the whole bill.

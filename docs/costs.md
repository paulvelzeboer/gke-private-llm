# Cost model

> **Estimates only.** Rough **europe-west4 on-demand** rates that change often; GPU Spot prices
> fluctuate hourly. Treat this as a shape, not a quote — confirm in the
> [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator). Excludes network
> egress, support, and taxes. ~730 hours/month assumed for always-on items.

## The two parts of the bill

A **fixed perimeter** (always on) and the **GPU** (dominant, variable — where Spot helps).

### Fixed perimeter — always on

| Component | Spec | ~ Rate | ~ Monthly |
|---|---|---|---|
| System node pool | 2× e2-standard-4 | ~$0.134/hr each | ~$196 |
| GKE control plane | 1 zonal cluster | $0.10/hr | ~$73 (often offset by the free-tier credit) |
| Jumpbox | e2-standard-2 | ~$0.067/hr | ~$49 (stop when idle) |
| Internal LB | 1 forwarding rule | ~$0.025/hr | ~$18 |
| Cloud Logging | after 50 GiB free | $0.50/GiB | ~$0–30 |
| Managed Prometheus | per samples | ~$0.06/M | ~$10–40 |
| GCS (weights) | ~150 GB Standard | $0.020/GB | ~$3 |
| Artifact Registry | ~10 GB | $0.10/GB | ~$1 |
| Cloud DNS | 3 private zones | $0.20/zone | ~$1 |
| **Perimeter subtotal** | | | **~$350–410** |

> **Notably cheaper perimeter than the Azure build.** The GCP air-gap uses free/near-free
> primitives — private nodes, *no* Cloud NAT, VPC firewall rules, and IAP — so there is no
> Azure-Firewall (~$900/mo) or Bastion (~$210/mo) equivalent on the bill. VPC flow logs are the
> main variable perimeter cost (by volume).

### GPU — the dominant, variable line

`a2-ultragpu-1g` = 1× A100 80 GB.

| Mode | ~ Rate | ~ Monthly (24/7) |
|---|---|---|
| On-demand | ~$3.9–5.1/hr | **~$2,850–3,700** |
| **Spot (this repo's default)** | ~$1.2–2.2/hr (varies) | **~$900–1,600** |
| Spot + scale-to-zero | pay only for running hours | e.g. ~170 h/mo ≈ **~$200–380** |

Spot typically saves **~60–90%** versus on-demand. Tradeoff: GCP can preempt a Spot node with
~30 seconds' notice, so the model pod may be evicted and reschedule. For a controlled internal
service that is usually fine; set `use_spot_gpu = false` for guaranteed capacity.

## Scenarios (perimeter + GPU)

| Scenario | ~ Monthly |
|---|---|
| On-demand GPU, 24/7 | **~$3,200–4,100** |
| **Spot GPU, 24/7 (default)** | **~$1,300–2,000** |
| Spot GPU, business hours + scale-to-zero | **~$550–790** |

With the GPU scaled down the perimeter dominates — and here that floor is only a few hundred
dollars, so the biggest lever by far remains the GPU.

## Cost levers (in rough order of impact)

1. **Keep Spot** (default) — the largest single saving.
2. **Scale the GPU pool to zero when idle.** `gpu_min_count = 0` lets the pool empty; to realise
   it, scale the vLLM Deployment to 0 (`kubectl -n llm scale deploy/vllm --replicas=0`) or drive
   it with an autoscaler on request volume.
3. **Stop the jumpbox when not in use** (`gcloud compute instances stop`).
4. **Smaller GPU** (`a2-highgpu-1g` = A100 40GB, or an L4 machine `g2-standard-*`) for smaller
   models cuts the GPU rate sharply.
5. **Right-size logging:** VPC flow-log sampling and Cloud Logging exclusion filters.

## Tuning knobs (Terraform variables)

| Variable | Default | Effect |
|---|---|---|
| `use_spot_gpu` | `true` | Spot vs on-demand GPU nodes |
| `gpu_min_count` | `0` | Autoscaler floor; `0` allows scale-to-zero |
| `gpu_node_count` | `1` | Initial GPU nodes |
| `gpu_max_count` | `3` | Autoscaler ceiling |
| `gpu_machine_type` | `a2-ultragpu-1g` | GPU machine type |
| `gpu_accelerator_type` | `nvidia-a100-80gb` | GPU type |

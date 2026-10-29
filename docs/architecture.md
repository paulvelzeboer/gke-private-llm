# Architecture & decisions

## Threat model / goals

1. **No model or data egress.** A compromised or misbehaving model pod must not reach the internet.
2. **No public attack surface.** Control plane, inference API, registry, and bucket are all private.
3. **Full attributable audit.** Every inference request and every blocked egress attempt is retained.
4. **Usable from a CLI** over an OpenAI-compatible API.

## Layered egress control (defence in depth)

| Layer | Mechanism | File |
|---|---|---|
| Pod | Dataplane V2 (Cilium) `default-deny` NetworkPolicy; only DNS + the one allowed hop | `kubernetes/base/10-network-policies.yaml` |
| Node → internet | **No Cloud NAT** and private nodes (no external IPs) → no outbound path exists | `terraform/nodepools.tf`, `gke.tf` |
| VPC edge | Explicit **deny-all egress** firewall rule; allow only the restricted-API VIP + intra-VPC | `terraform/network.tf` |
| Google APIs | Private Google Access + private DNS → `restricted.googleapis.com` (199.36.153.4/30) | `terraform/network.tf` |
| Artifact sources | Artifact Registry + GCS, IAM-gated, pulled over the restricted VIP | `terraform/registry.tf` |
| Runtime | `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1` on vLLM | `kubernetes/base/30-vllm.yaml` |

Because there is no Cloud NAT and the nodes have no external IPs, there is literally no route to
the public internet — the firewall deny-all is belt-and-braces and, with VPC flow logs, the audit
point. Google APIs are reached only through the private restricted VIP.

## Key decisions

**vLLM over Ollama / Vertex.** This is a *self-hosted, fully controlled* model, so managed Vertex
AI is out of scope by design. vLLM gives production throughput and OpenAI-compatible tool calling.

**GKE-managed GPU driver.** Setting `gpu_driver_version = LATEST` makes GKE install the NVIDIA
driver and device plugin automatically from Google-hosted images over the restricted VIP — no
manual device-plugin DaemonSet and no third-party registry access (simpler than the AKS equivalent).

**LiteLLM as the gateway.** Single control/audit plane: OpenAI-compatible surface, virtual keys
with budgets/limits, per-request logging. vLLM stays unauthenticated-but-unreachable (only the
gateway can reach it, enforced by NetworkPolicy).

**Internal passthrough LB, not Ingress.** The brief is a private endpoint for CLI clients, not a
public web app. `networking.gke.io/load-balancer-type: Internal` gives a stable private VPC IP.

**GMP + Cloud Monitoring, not a self-hosted stack.** Google Managed Service for Prometheus scrapes
vLLM/LiteLLM via `PodMonitoring`; Cloud Logging holds the forensic record; a Cloud Monitoring
dashboard visualises it. Nothing new to operate or secure. The same PromQL also works in Grafana
against a GMP data source if preferred.

**IAP + jumpbox for access.** The control plane uses a private endpoint, so kubectl and the LLM
endpoint are only reachable from inside the VPC. An IAP TCP tunnel to a no-external-IP jumpbox
replaces a public bastion; OS Login + IAM replace static SSH keys.

## The one controlled ingress

`scripts/seed-artifacts.sh` is the single, deliberate door into the air-gap: `crane copy` pushes
images into Artifact Registry and the weights upload to GCS. It runs once, from an operator host,
and is the thing to gate with change control. After it, the cluster needs no internet.

## Hardening path

- **VPC Service Controls** perimeter around the project so Artifact Registry/GCS/Logging cannot be
  reached from outside the perimeter even with valid credentials — the strongest form of the air-gap.
- **Binary Authorization** to allow only signed images from the private repo.
- **Private DNS only** (disable the metadata DNS egress rule) once an in-VPC resolver is in place.

## Scaling

- **More throughput:** raise `gpu_max_count` and vLLM `replicas`; LiteLLM round-robins.
- **Bigger model:** multi-GPU machine type (`a2-ultragpu-2g`/`4g`/`8g`) + `--tensor-parallel-size=N`.
- **Idle cost:** Spot pool with `gpu_min_count = 0`; scale vLLM to 0 to drop GPU nodes entirely.

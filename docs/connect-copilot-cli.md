# Connect GitHub Copilot CLI to the private LLM

GitHub Copilot CLI supports a **custom OpenAI-compatible model provider (BYOK)**, so you can point
it at this platform's private endpoint instead of GitHub's hosted models. The vLLM server here is
OpenAI-compatible with tool calling + streaming enabled, which Copilot CLI requires.

> **Where this runs:** Copilot CLI runs on the **operator side** — the jumpbox (reached over IAP),
> not inside the air-gapped cluster. The CLI still talks to GitHub to authenticate the agent, but
> **model inference is routed to your private endpoint**. Run it from the jumpbox so it can reach
> the internal load balancer over the VPC. The cluster stays air-gapped regardless.

## Prerequisites

- Copilot CLI installed and signed in: `npm install -g @github/copilot` then `copilot`.
  A Copilot subscription is still required to run the agent.
- A LiteLLM **virtual key** (`LLM_KEY`) minted from the gateway master key.
- You are on the jumpbox (`gcloud compute ssh <jumpbox> --tunnel-through-iap`) with VPC reach to
  the gateway's internal IP.

## Configure the custom provider

```bash
GW_IP=$(kubectl -n gateway get svc litellm -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

export COPILOT_PROVIDER_BASE_URL="http://${GW_IP}:4000/v1"
export COPILOT_MODEL="private-llm"          # vLLM served-model-name
export COPILOT_PROVIDER_API_KEY="$LLM_KEY"  # LiteLLM virtual key
```

Then:

```bash
copilot                       # interactive; then /model private-llm
# or non-interactively:
copilot -p "Explain what terraform/network.tf enforces." --model private-llm
```

## Notes & gotchas

- **Tool calling is mandatory.** Copilot CLI only works with models that support function calling
  and streaming. The deployment enables this (`--enable-auto-tool-choice --tool-call-parser
  llama3_json`); set the matching parser if you swap model family. See [running-a-model.md](running-a-model.md).
- **Single auth header only.** Copilot CLI sends one `Authorization` header and cannot send custom
  headers — the LiteLLM virtual key works fine.
- **HTTPS in production.** The example uses `http://` on the internal LB. For anything beyond a lab,
  terminate TLS and use `https://`.
- **Variable names can change.** BYOK in Copilot CLI is evolving; if `COPILOT_PROVIDER_*` is
  rejected, check the current page:
  <https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models>.

## Prefer a pure-OSS client?

Any base-URL-aware client gives the same experience against the same endpoint — see
`scripts/connect-cli.sh` for `llm`, `aider`, and the OpenAI SDK.

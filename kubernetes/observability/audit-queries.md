# Audit & monitoring queries (Cloud Logging)

VPC flow logs, firewall logging, and workload stdout all land in Cloud Logging; GMP holds the
metrics. Run these in **Logs Explorer** (or `gcloud logging read '<query>'`). No extra agent needed.

## 1. Blocked egress — proof the air-gap holds
Every connection the deny-all egress rule dropped.

```
logName=~"logs/compute.googleapis.com%2Ffirewall"
jsonPayload.rule_details.reference=~"fw-privllm-egress-deny-all"
jsonPayload.disposition="DENIED"
```

## 2. Allowed egress audit (should be restricted-VIP + intra-VPC only)

```
logName=~"logs/compute.googleapis.com%2Ffirewall"
jsonPayload.disposition="ALLOWED"
jsonPayload.connection.dest_ip="199.36.153.4"
```

## 3. Every LLM request/response through the gateway
LiteLLM logs each call (who, model, tokens, latency) to stdout.

```
resource.type="k8s_container"
resource.labels.namespace_name="gateway"
resource.labels.container_name="litellm"
```

## 4. vLLM server logs

```
resource.type="k8s_container"
resource.labels.namespace_name="llm"
resource.labels.container_name="vllm"
```

## 5. Who called with which virtual key (attribution)

```
resource.type="k8s_container"
resource.labels.namespace_name="gateway"
textPayload=~"api_key|user"
```

## 6. Suggested alert — egress Deny spike
Create a **log-based metric** on query 1, then a Monitoring alert that fires when its rate > 0.
That is the tripwire for anything probing the air-gap.

## Metrics / dashboards
vLLM + gateway metrics are scraped by Google Managed Service for Prometheus (see
`podmonitoring.yaml`) and shown on the Cloud Monitoring dashboard created in
`terraform/monitoring.tf`. The same PromQL works in Grafana via a GMP data source
(`grafana-dashboard-vllm.json`).

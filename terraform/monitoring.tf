# ---------------------------------------------------------------------------
# Cloud Monitoring dashboard fed by Google Managed Service for Prometheus (GMP,
# enabled on the cluster). vLLM/LiteLLM metrics are scraped by GMP via the
# PodMonitoring CRs in kubernetes/observability and queried here with PromQL.
# This is the first-party equivalent of the Azure Managed Grafana dashboard;
# the same metrics also work in Grafana via a GMP data source (see that dir).
# ---------------------------------------------------------------------------
resource "google_monitoring_dashboard" "vllm" {
  dashboard_json = jsonencode({
    displayName = "Private LLM - vLLM & Gateway"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width = 6, height = 4, xPos = 0, yPos = 0
          widget = {
            title = "Requests running vs waiting"
            xyChart = { dataSets = [
              { timeSeriesQuery = { prometheusQuery = "sum(vllm:num_requests_running)" } },
              { timeSeriesQuery = { prometheusQuery = "sum(vllm:num_requests_waiting)" } },
            ] }
          }
        },
        {
          width = 6, height = 4, xPos = 6, yPos = 0
          widget = {
            title = "KV-cache usage %"
            xyChart = { dataSets = [
              { timeSeriesQuery = { prometheusQuery = "avg(vllm:gpu_cache_usage_perc)" } },
            ] }
          }
        },
        {
          width = 6, height = 4, xPos = 0, yPos = 4
          widget = {
            title = "Token throughput (tokens/s)"
            xyChart = { dataSets = [
              { timeSeriesQuery = { prometheusQuery = "sum(rate(vllm:prompt_tokens_total[5m]))" } },
              { timeSeriesQuery = { prometheusQuery = "sum(rate(vllm:generation_tokens_total[5m]))" } },
            ] }
          }
        },
        {
          width = 6, height = 4, xPos = 6, yPos = 4
          widget = {
            title = "End-to-end request latency p95 (s)"
            xyChart = { dataSets = [
              { timeSeriesQuery = { prometheusQuery = "histogram_quantile(0.95, sum by (le) (rate(vllm:e2e_request_latency_seconds_bucket[5m])))" } },
            ] }
          }
        },
        {
          width = 12, height = 4, xPos = 0, yPos = 8
          widget = {
            title = "Gateway requests/s by key"
            xyChart = { dataSets = [
              { timeSeriesQuery = { prometheusQuery = "sum by (api_key_alias) (rate(litellm_requests_metric_total[5m]))" } },
            ] }
          }
        },
      ]
    }
  })
}

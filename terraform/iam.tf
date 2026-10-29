# Dedicated least-privilege node service account (replaces the default SA,
# which has broad editor-ish scopes). Nodes may pull images, write logs/metrics,
# and read the weights bucket — nothing else.
resource "google_service_account" "nodes" {
  account_id   = "${var.prefix}-nodes"
  display_name = "GKE nodes - private LLM"
}

locals {
  node_roles = [
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ]
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.nodes.email}"
}

# Workload Identity: the vLLM Kubernetes SA (llm/vllm) impersonates a GCP SA
# that can read ONLY the weights bucket. No node-wide storage access.
resource "google_service_account" "weights_reader" {
  account_id   = "${var.prefix}-weights"
  display_name = "vLLM weights reader"
}

resource "google_service_account_iam_member" "weights_wi" {
  service_account_id = google_service_account.weights_reader.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[llm/vllm]"
}

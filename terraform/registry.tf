# ---------------------------------------------------------------------------
# Artifact Registry (images) + GCS bucket (model weights). Both private: access
# is IAM-gated and reached over the restricted VIP via Private Google Access, so
# nothing traverses the public internet after the one-time seeding.
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository" "images" {
  repository_id = "${var.prefix}-images"
  location      = var.region
  format        = "DOCKER"
  description   = "Private images for the air-gapped LLM platform"
  labels        = var.labels
}

resource "google_storage_bucket" "weights" {
  name                        = "${var.project_id}-${var.prefix}-weights"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = var.labels
}

# vLLM's Workload-Identity SA may read weights; nothing else.
resource "google_storage_bucket_iam_member" "weights_reader" {
  bucket = google_storage_bucket.weights.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.weights_reader.email}"
}

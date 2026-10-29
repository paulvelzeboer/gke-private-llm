# ---------------------------------------------------------------------------
# Operator access. The control plane and the LLM endpoint are both private, so
# humans reach them through a jumpbox with NO external IP, over an IAP TCP
# tunnel. From the jumpbox they run kubectl, seed artifacts, and point CLI
# clients at the internal LLM load balancer.
# ---------------------------------------------------------------------------
resource "google_service_account" "jumpbox" {
  account_id   = "${var.prefix}-jumpbox"
  display_name = "Operator jumpbox"
}

locals {
  jumpbox_roles = [
    "roles/container.developer",       # get-credentials + kubectl
    "roles/artifactregistry.writer",   # seed images
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]
}

resource "google_project_iam_member" "jumpbox" {
  for_each = toset(local.jumpbox_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.jumpbox.email}"
}

# Jumpbox may upload weights to the bucket (seeding).
resource "google_storage_bucket_iam_member" "jumpbox_weights_admin" {
  bucket = google_storage_bucket.weights.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.jumpbox.email}"
}

resource "google_compute_instance" "jumpbox" {
  name         = "vm-${var.prefix}-jump"
  machine_type = "e2-standard-2"
  zone         = var.zone
  tags         = ["jumpbox"]

  boot_disk {
    initialize_params { image = "debian-cloud/debian-12" }
  }

  # No access_config block => no external IP. Internet-free; uses PGA for APIs.
  network_interface {
    subnetwork = google_compute_subnetwork.nodes.id
  }

  service_account {
    email  = google_service_account.jumpbox.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE"
  }
}

# Operators allowed to tunnel in via IAP and SSH (OS Login). Set to your
# user/group, e.g. "user:you@example.com" or "group:platform@example.com".
variable "iap_members" {
  description = "Principals allowed to reach the jumpbox over IAP (SSH)."
  type        = list(string)
  default     = []
}

resource "google_project_iam_member" "iap_tunnel" {
  for_each = toset(var.iap_members)
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}

resource "google_project_iam_member" "iap_oslogin" {
  for_each = toset(var.iap_members)
  project  = var.project_id
  role     = "roles/compute.osLogin"
  member   = each.value
}

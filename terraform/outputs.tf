output "cluster_name" {
  value = google_container_cluster.this.name
}

output "cluster_location" {
  value = google_container_cluster.this.location
}

output "artifact_registry" {
  description = "Docker repo host/path for seeded images."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "weights_bucket" {
  value = google_storage_bucket.weights.name
}

output "weights_reader_sa" {
  value = google_service_account.weights_reader.email
}

output "jumpbox_name" {
  value = google_compute_instance.jumpbox.name
}

output "ssh_to_jumpbox_cmd" {
  description = "IAP tunnel SSH to the jumpbox (no external IP needed)."
  value       = "gcloud compute ssh ${google_compute_instance.jumpbox.name} --zone ${var.zone} --tunnel-through-iap"
}

output "get_credentials_cmd" {
  description = "Run on the jumpbox to get kubectl access to the private API."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --location ${var.zone} --internal-ip"
}

# System pool: small, CPU-only; runs the gateway, kube-system, GMP collectors.
resource "google_container_node_pool" "system" {
  name     = "system"
  cluster  = google_container_cluster.this.id
  location = var.zone

  autoscaling {
    min_node_count = 2
    max_node_count = 3
  }

  node_config {
    machine_type    = "e2-standard-4"
    image_type      = "COS_CONTAINERD"
    disk_size_gb    = 100
    disk_type       = "pd-balanced"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = var.labels

    workload_metadata_config { mode = "GKE_METADATA" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  lifecycle { ignore_changes = [node_config[0].labels] }
}

# ---------------------------------------------------------------------------
# GPU pool: Spot a2-ultragpu-1g (1x A100 80GB). GKE installs the NVIDIA driver
# and device plugin automatically (gpu_driver_version), so no manual daemonset.
# TRADEOFF: Spot nodes can be preempted with ~30s notice; the model pod will be
# evicted and reschedule when capacity returns. min_node_count = 0 lets the pool
# scale to zero (scale vLLM to 0 to realise it).
# ---------------------------------------------------------------------------
resource "google_container_node_pool" "gpu" {
  name     = "gpu"
  cluster  = google_container_cluster.this.id
  location = var.zone

  initial_node_count = var.gpu_node_count
  autoscaling {
    min_node_count = var.gpu_min_count
    max_node_count = var.gpu_max_count
  }

  node_config {
    machine_type    = var.gpu_machine_type
    image_type      = "COS_CONTAINERD"
    disk_size_gb    = 250
    disk_type       = "pd-ssd"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    spot            = var.use_spot_gpu

    labels = merge(var.labels, { workload = "llm", accelerator = "nvidia" })

    guest_accelerator {
      type  = var.gpu_accelerator_type
      count = 1
      gpu_driver_installation_config {
        gpu_driver_version = "LATEST" # GKE auto-installs driver + device plugin
      }
    }

    # Keep non-GPU/non-LLM pods off these expensive nodes. Pods tolerate the
    # GPU taint and (when Spot) the gke-spot taint; see kubernetes/base.
    taint {
      key    = "nvidia.com/gpu"
      value  = "present"
      effect = "NO_SCHEDULE"
    }
    dynamic "taint" {
      for_each = var.use_spot_gpu ? [1] : []
      content {
        key    = "cloud.google.com/gke-spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    }

    workload_metadata_config { mode = "GKE_METADATA" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  lifecycle { ignore_changes = [initial_node_count, node_config[0].labels] }
}

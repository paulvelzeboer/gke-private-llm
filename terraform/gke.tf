# ---------------------------------------------------------------------------
# Private GKE cluster. The control plane has a private endpoint only; nodes have
# no external IPs. Dataplane V2 (Cilium) provides NetworkPolicy enforcement.
# Google Managed Service for Prometheus + Cloud Logging/Monitoring are built in.
# ---------------------------------------------------------------------------
resource "google_container_cluster" "this" {
  provider = google-beta
  name     = "gke-${var.prefix}"
  location = var.zone # zonal: A100 availability is zonal, keeps nodes co-located

  network    = google_compute_network.this.id
  subnetwork = google_compute_subnetwork.nodes.id

  networking_mode  = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH" # Dataplane V2 -> NetworkPolicy + flow logs

  # We manage node pools explicitly; drop the default pool.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel { channel = "REGULAR" }

  # Set to true for production so a stray destroy can't delete the cluster.
  deletion_protection = false

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true # no public control-plane endpoint
    master_ipv4_cidr_block  = var.master_cidr

    master_global_access_config { enabled = false }
  }

  # Only the jumpbox subnet may reach the private API server.
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.subnet_nodes_cidr
      display_name = "vpc-nodes-and-jumpbox"
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    gcs_fuse_csi_driver_config { enabled = true } # mount weights from GCS
    http_load_balancing { disabled = true }
  }

  # Managed Prometheus + full logging/monitoring.
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "WORKLOADS"]
    managed_prometheus { enabled = true }
  }
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  resource_labels = var.labels

  depends_on = [
    google_compute_firewall.egress_deny_all,
    google_compute_firewall.egress_allow_restricted_apis,
    google_dns_record_set.restricted_wildcard,
  ]
}

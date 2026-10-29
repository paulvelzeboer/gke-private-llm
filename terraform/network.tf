# ---------------------------------------------------------------------------
# VPC. No auto subnets, no Cloud NAT — so nodes have NO path to the internet.
# The only egress permitted is to Google APIs over the restricted VIP (via
# Private Google Access) and intra-cluster traffic. Everything else is denied
# by an explicit deny-all egress rule and logged.
# ---------------------------------------------------------------------------
resource "google_compute_network" "this" {
  name                    = "vpc-${var.prefix}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "nodes" {
  name                     = "snet-${var.prefix}-nodes"
  ip_cidr_range            = var.subnet_nodes_cidr
  region                   = var.region
  network                  = google_compute_network.this.id
  private_ip_google_access = true # reach Google APIs with no external IP

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  # VPC flow logs = the network audit record (the "monitored" half of egress).
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 1.0
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# The restricted VIP that Private Google Access routes *.googleapis.com to.
# Deliberately NOT a route to the internet — it is Google's private frontend.
resource "google_compute_route" "restricted_apis" {
  name             = "rt-${var.prefix}-restricted-apis"
  network          = google_compute_network.this.id
  dest_range       = "199.36.153.4/30"
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
}

# ---------------------------------------------------------------------------
# Egress firewall: DEFAULT DENY. Allow only the restricted API VIP, intra-VPC,
# and node DNS/metadata. Nothing reaches the public internet.
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "egress_allow_restricted_apis" {
  name      = "fw-${var.prefix}-egress-apis"
  network   = google_compute_network.this.id
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = ["199.36.153.4/30"]
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

resource "google_compute_firewall" "egress_allow_internal" {
  name      = "fw-${var.prefix}-egress-internal"
  network   = google_compute_network.this.id
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = [
    var.subnet_nodes_cidr,
    var.pods_cidr,
    var.services_cidr,
    var.master_cidr,
  ]
  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}

resource "google_compute_firewall" "egress_allow_dns_metadata" {
  name      = "fw-${var.prefix}-egress-dns-metadata"
  network   = google_compute_network.this.id
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = ["169.254.169.254/32"]
  allow {
    protocol = "tcp"
    ports    = ["53", "80", "988"]
  }
  allow {
    protocol = "udp"
    ports    = ["53"]
  }
}

resource "google_compute_firewall" "egress_deny_all" {
  name      = "fw-${var.prefix}-egress-deny-all"
  network   = google_compute_network.this.id
  direction = "EGRESS"
  priority  = 2000

  destination_ranges = ["0.0.0.0/0"]
  deny { protocol = "all" }
  # Log every blocked attempt — proof the air-gap holds.
  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

# ---------------------------------------------------------------------------
# Ingress: IAP (for the jumpbox) and internal load-balancer health checks only.
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "ingress_iap_ssh" {
  name      = "fw-${var.prefix}-ingress-iap"
  network   = google_compute_network.this.id
  direction = "INGRESS"
  priority  = 1000

  # IAP's TCP-forwarding source range.
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["jumpbox"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

resource "google_compute_firewall" "ingress_health_checks" {
  name      = "fw-${var.prefix}-ingress-hc"
  network   = google_compute_network.this.id
  direction = "INGRESS"
  priority  = 1000

  # Google front-end / health-check ranges for the internal LB.
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  allow { protocol = "tcp" }
}

# ---------------------------------------------------------------------------
# Private DNS so *.googleapis.com / pkg.dev / gcr.io resolve to the restricted
# VIP. Without this, image and weight pulls would try the public internet and
# be denied.
# ---------------------------------------------------------------------------
locals {
  restricted_zones = {
    googleapis = "googleapis.com."
    gcr        = "gcr.io."
    pkgdev     = "pkg.dev."
  }
}

resource "google_dns_managed_zone" "restricted" {
  for_each   = local.restricted_zones
  name       = "${var.prefix}-${each.key}"
  dns_name   = each.value
  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.this.id
    }
  }
}

resource "google_dns_record_set" "restricted_a" {
  for_each     = local.restricted_zones
  name         = "restricted.${each.value}"
  managed_zone = google_dns_managed_zone.restricted[each.key].name
  type         = "A"
  ttl          = 300
  rrdatas      = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]
}

resource "google_dns_record_set" "restricted_wildcard" {
  for_each     = local.restricted_zones
  name         = "*.${each.value}"
  managed_zone = google_dns_managed_zone.restricted[each.key].name
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["restricted.${each.value}"]
}

variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
}

variable "prefix" {
  description = "Short name prefix for all resources."
  type        = string
  default     = "privllm"
}

variable "region" {
  description = "GCP region. Must have the chosen GPU type available."
  type        = string
  default     = "europe-west4"
}

variable "zone" {
  description = "Zone for the GPU node pool (A100 availability is zonal)."
  type        = string
  default     = "europe-west4-a"
}

# ---------------------------------------------------------------------------
# Addressing. Primary subnet for nodes; secondary ranges for Pods and Services
# (VPC-native). The control plane gets its own /28 (Google-managed).
# ---------------------------------------------------------------------------
variable "subnet_nodes_cidr" {
  type    = string
  default = "10.42.0.0/20"
}

variable "pods_cidr" {
  type    = string
  default = "10.44.0.0/16"
}

variable "services_cidr" {
  type    = string
  default = "10.46.0.0/20"
}

variable "master_cidr" {
  description = "Private control-plane endpoint range (/28)."
  type        = string
  default     = "172.16.0.0/28"
}

# ---------------------------------------------------------------------------
# GPU node pool. a2-ultragpu-1g = 1x A100 80GB. Spot by default (cost).
# ---------------------------------------------------------------------------
variable "gpu_machine_type" {
  type    = string
  default = "a2-ultragpu-1g"
}

variable "gpu_accelerator_type" {
  type    = string
  default = "nvidia-a100-80gb"
}

variable "gpu_node_count" {
  description = "Initial GPU node count."
  type        = number
  default     = 1
}

variable "gpu_min_count" {
  description = "Autoscaler floor. 0 lets the Spot pool scale to zero when idle."
  type        = number
  default     = 0
}

variable "gpu_max_count" {
  type    = number
  default = 3
}

variable "use_spot_gpu" {
  description = "Run the GPU pool on Spot VMs (~60-90% cheaper, preemptible)."
  type        = bool
  default     = true
}

variable "labels" {
  type = map(string)
  default = {
    workload   = "private-llm"
    managed-by = "terraform"
    egress     = "air-gapped"
  }
}

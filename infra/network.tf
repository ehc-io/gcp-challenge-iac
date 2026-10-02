resource "google_compute_network" "vpc" {
  name                    = "ehc-vpc"
  auto_create_subnetworks = false # custom mode: only the subnets below exist
  routing_mode            = "REGIONAL"
}

# Public subnet: MongoDB VM (external IP)
resource "google_compute_subnetwork" "public" {
  name          = "ehc-subnet-public"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_public_cidr

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Private subnet: GKE nodes (no external IPs) + VPC-native secondary ranges
resource "google_compute_subnetwork" "gke" {
  name                     = "ehc-subnet-gke"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_gke_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "ehc-pods"
    ip_cidr_range = var.gke_pods_cidr
  }

  secondary_ip_range {
    range_name    = "ehc-services"
    ip_cidr_range = var.gke_services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "router" {
  name    = "ehc-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Egress for private GKE nodes and Pods only; the public subnet is not NATed
resource "google_compute_router_nat" "nat" {
  name                               = "ehc-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"] # primary (nodes) + secondary (Pods)
  }

  log_config {
    enable = true
    filter = "ALL"
  }
}

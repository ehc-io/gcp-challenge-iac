# Ingress not allowed by these rules is dropped by the VPC's implied deny-all ingress rule.

# SSH to the MongoDB VM from any source
resource "google_compute_firewall" "ssh_any" {
  name          = "ehc-fw-ssh-any"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.mongo_vm_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# MongoDB reachable only from the GKE node range and the Pod range (VPC-native: Pods egress with their own IP)
resource "google_compute_firewall" "mongo_from_gke" {
  name          = "ehc-fw-mongo-from-gke"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.subnet_gke_cidr, var.gke_pods_cidr]
  target_tags   = [var.mongo_vm_tag]

  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Google Front Ends -> application Pods. The external Application Load Balancer proxies client
# requests and sends health-check probes from these same Google ranges, to Pod IPs (NEG) on the app port.
resource "google_compute_firewall" "lb_to_gke" {
  name          = "ehc-fw-lb-to-gke"
  description   = "External Application Load Balancer (proxied traffic and health checks) to the application port on GKE nodes and Pods"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = [var.gke_node_tag]

  allow {
    protocol = "tcp"
    ports    = [var.app_port]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

moved {
  from = google_compute_firewall.lb_health_checks
  to   = google_compute_firewall.lb_to_gke
}

# Dedicated node identity: GKE node baseline permissions only, instead of the Compute Engine default SA
resource "google_service_account" "gke_nodes" {
  account_id   = "ehc-gke-nodes"
  display_name = "GKE nodes"
  description  = "Identity of the GKE node VMs"
}

# Logging, monitoring and other permissions GKE nodes need to operate
resource "google_project_iam_member" "gke_nodes_default" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = google_service_account.gke_nodes.member
}

#trivy:ignore:AVD-GCP-0061 the IP-based control plane endpoints are disabled; access is only through the IAM-authenticated DNS endpoint
resource "google_container_cluster" "gke" {
  name     = "ehc-gke"
  location = var.zone

  network         = google_compute_network.vpc.id
  subnetwork      = google_compute_subnetwork.gke.id
  networking_mode = "VPC_NATIVE"

  # Dataplane V2 (eBPF): enforces Kubernetes NetworkPolicy
  datapath_provider = "ADVANCED_DATAPATH"

  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.gke.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.gke.secondary_ip_range[1].range_name
  }

  # Nodes get internal IPs only; egress goes through Cloud NAT
  private_cluster_config {
    enable_private_nodes = true
  }

  # Control plane reachable only through the DNS-based endpoint (IAM-authenticated, container.clusters.connect).
  # The IP-based endpoints (external and internal) are turned off.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
    ip_endpoints_config {
      enabled = false
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  enable_shielded_nodes = true

  # The default node pool is replaced by the managed pool below. It still boots briefly,
  # so it also runs as the dedicated node SA rather than the Compute Engine default SA.
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  deletion_protection = false

  lifecycle {
    ignore_changes = [node_config]
  }

  depends_on = [
    google_project_iam_member.gke_nodes_default,
    google_binary_authorization_policy.policy,
  ]
}

#trivy:ignore:AVD-GCP-0048 Pods use the GKE metadata server (GKE_METADATA); legacy metadata endpoints are not served by current GKE versions
resource "google_container_node_pool" "default" {
  name     = "ehc-pool"
  cluster  = google_container_cluster.gke.id
  location = var.zone

  node_count = var.gke_node_count

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.gke_machine_type
    image_type   = "COS_CONTAINERD"
    disk_type    = "pd-balanced"
    disk_size_gb = 50

    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Target of the load balancer health-check firewall rule
    tags = [var.gke_node_tag]

    # Pods see the GKE metadata server (Workload Identity), not the node's metadata and SA token
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  depends_on = [google_artifact_registry_repository_iam_member.app_gke_nodes_reader]
}

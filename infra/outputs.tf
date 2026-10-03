output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "subnet_public" {
  value = google_compute_subnetwork.public.self_link
}

output "subnet_gke" {
  value = google_compute_subnetwork.gke.self_link
}

output "gke_pods_range_name" {
  value = google_compute_subnetwork.gke.secondary_ip_range[0].range_name
}

output "gke_services_range_name" {
  value = google_compute_subnetwork.gke.secondary_ip_range[1].range_name
}

output "mongo_vm_name" {
  value = google_compute_instance.mongo.name
}

output "mongo_vm_internal_ip" {
  value = google_compute_address.mongo_internal.address
}

output "mongo_vm_external_ip" {
  value = google_compute_instance.mongo.network_interface[0].access_config[0].nat_ip
}

output "mongo_vm_service_account" {
  value = google_service_account.mongo_vm.email
}

output "mongo_secret_ids" {
  value = {
    admin  = google_secret_manager_secret.mongo_admin_pw.secret_id
    app    = google_secret_manager_secret.mongo_app_pw.secret_id
    backup = google_secret_manager_secret.mongo_backup_pw.secret_id
  }
}

output "mongo_backup_bucket" {
  value = google_storage_bucket.mongo_backups.name
}

output "mongo_backup_bucket_url" {
  value = "https://storage.googleapis.com/${google_storage_bucket.mongo_backups.name}"
}

output "artifact_registry_repo" {
  value = google_artifact_registry_repository.app.registry_uri
}

output "gke_cluster_name" {
  value = google_container_cluster.gke.name
}

output "gke_dns_endpoint" {
  value = google_container_cluster.gke.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "gke_node_service_account" {
  value = google_service_account.gke_nodes.email
}

output "app_security_policy" {
  value = google_compute_security_policy.app.name
}

output "app_ingress_ip_name" {
  value = google_compute_global_address.app_ingress.name
}

output "app_ingress_ip" {
  value = google_compute_global_address.app_ingress.address
}

output "app_port" {
  value = var.app_port
}

output "github_wif_provider" {
  description = "Workload Identity Federation provider resource name for GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deployer_service_accounts" {
  description = "Deployer service account emails"
  value = {
    iac = google_service_account.deployer_iac.email
    app = google_service_account.deployer_app.email
  }
}

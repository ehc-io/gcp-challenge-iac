# Private Docker registry for application images
resource "google_artifact_registry_repository" "app" {
  repository_id = "ehc-app"
  location      = var.region
  format        = "DOCKER"
  description   = "Application container images"

  # A pushed tag can never be moved to a different image
  docker_config {
    immutable_tags = true
  }

  # Automatic vulnerability scanning of pushed images (Container Scanning API)
  vulnerability_scanning_config {
    enablement_config = "INHERITED"
  }
}

# GKE nodes pull images from this repository only (no project-wide registry access)
resource "google_artifact_registry_repository_iam_member" "app_gke_nodes_reader" {
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.reader"
  member     = google_service_account.gke_nodes.member
}

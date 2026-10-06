# GitHub Actions authenticates with short-lived OIDC tokens exchanged through this pool.
# No service account keys exist anywhere in the pipelines.
locals {
  github_repo_iac = "ehc-io/gcp-challenge-iac"
  github_repo_app = "ehc-io/gcp-challenge-app"
  tfstate_bucket  = "clgcporg10-178-tfstate"
}

resource "google_project_service" "ondemandscanning" {
  service            = "ondemandscanning.googleapis.com"
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "ehc-github-pool"
  display_name              = "GitHub Actions"
  description               = "Identities for GitHub Actions workflows"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "ehc-github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # Only workflows from these two repositories can obtain a token at all
  attribute_condition = "assertion.repository_owner == \"ehc-io\" && assertion.repository in [\"${local.github_repo_iac}\", \"${local.github_repo_app}\"]"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Terraform identity: used by the infrastructure repository only
resource "google_service_account" "deployer_iac" {
  account_id   = "ehc-deployer-iac"
  display_name = "Terraform deployer (GitHub Actions)"
}

resource "google_service_account_iam_member" "deployer_iac_wif" {
  service_account_id = google_service_account.deployer_iac.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.github_repo_iac}"
}

locals {
  deployer_iac_roles = toset([
    "roles/compute.admin",
    "roles/container.admin",
    "roles/artifactregistry.admin",
    "roles/secretmanager.admin",
    "roles/storage.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/binaryauthorization.policyEditor",
    "roles/binaryauthorization.attestorsAdmin",
    "roles/cloudkms.admin",
    "roles/cloudkms.publicKeyViewer",
    "roles/containeranalysis.admin",
    "roles/logging.configWriter",
    "roles/monitoring.editor",
    "roles/serviceusage.serviceUsageAdmin",
  ])
}

resource "google_project_iam_member" "deployer_iac" {
  for_each = local.deployer_iac_roles
  project  = var.project_id
  role     = each.value
  member   = google_service_account.deployer_iac.member
}

resource "google_storage_bucket_iam_member" "deployer_iac_state" {
  bucket = local.tfstate_bucket
  role   = "roles/storage.objectAdmin"
  member = google_service_account.deployer_iac.member
}

# Application identity: production deployments of the application repository only.
# Registry write on one repository and cluster connect; Kubernetes RBAC grants the rest.
resource "google_service_account" "deployer_app" {
  account_id   = "ehc-deployer-app"
  display_name = "Application deployer (GitHub Actions)"
}

locals {
  # GitHub OIDC subject (immutable format) of jobs running in the application repository's
  # "production" environment. GitHub only admits main-branch runs approved by a reviewer.
  github_app_deploy_subject = "repo:ehc-io@24269599/gcp-challenge-app@1401507441:environment:production"
}

resource "google_service_account_iam_member" "deployer_app_wif" {
  service_account_id = google_service_account.deployer_app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/${local.github_app_deploy_subject}"
}

resource "google_artifact_registry_repository_iam_member" "deployer_app_writer" {
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.deployer_app.member
}

resource "google_project_iam_member" "deployer_app_cluster_viewer" {
  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = google_service_account.deployer_app.member
}

# Image scanning identity: any branch of the application repository, including pull requests.
# On-Demand Scanning only: no registry write, no cluster access.
resource "google_service_account" "scanner_app" {
  account_id   = "ehc-scanner-app"
  display_name = "Image scanner (GitHub Actions)"
}

resource "google_service_account_iam_member" "scanner_app_wif" {
  service_account_id = google_service_account.scanner_app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.github_repo_app}"
}

resource "google_project_iam_member" "scanner_app_scan" {
  project = var.project_id
  role    = "roles/ondemandscanning.admin"
  member  = google_service_account.scanner_app.member
}

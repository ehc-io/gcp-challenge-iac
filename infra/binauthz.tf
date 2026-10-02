# Project Binary Authorization policy, enforced on clusters that use PROJECT_SINGLETON_POLICY_ENFORCE.
# Only images from the application repository are admitted; everything else is blocked and audit-logged.
resource "google_binary_authorization_policy" "policy" {
  description = "Admit application images from Artifact Registry only"

  # Google-maintained system images needed by GKE (kube-system, managed add-ons)
  global_policy_evaluation_mode = "ENABLE"

  admission_whitelist_patterns {
    name_pattern = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}/**"
  }

  default_admission_rule {
    evaluation_mode  = "ALWAYS_DENY"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  }
}

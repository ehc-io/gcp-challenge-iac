# Cloud Armor backend security policy for the application's external load balancer.
# Attached to the Ingress backend through a GKE BackendConfig (k8s/backendconfig.yaml).
# Only the listed source IPs reach the app; everything else gets 403 at Google's edge.
resource "google_compute_security_policy" "app" {
  name        = "ehc-app-armor"
  description = "Allowlist for the tasky web application; all other sources denied"
  type        = "CLOUD_ARMOR"

  rule {
    action      = "allow"
    priority    = 1000
    description = "home-ip: allowed client source ranges"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = var.app_allowed_source_ranges
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 2147483647
    description = "deny-all: default rule"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  advanced_options_config {
    log_level = "VERBOSE"
  }
}

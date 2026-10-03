# Security alerts on the GKE Admin Activity audit log.
# Matched-log conditions notify per event, with the principal and request in the incident.
resource "google_monitoring_notification_channel" "security_email" {
  display_name = "Security alerts (email)"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_alert_policy" "cluster_admin_binding" {
  display_name = "GKE: cluster-admin ClusterRoleBinding created"
  combiner     = "OR"

  conditions {
    display_name = "ClusterRoleBinding referencing cluster-admin"
    condition_matched_log {
      filter = <<-EOT
        resource.type="k8s_cluster"
        resource.labels.cluster_name="${google_container_cluster.gke.name}"
        logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Factivity"
        protoPayload.methodName="io.k8s.authorization.rbac.v1.clusterrolebindings.create"
        protoPayload.request.roleRef.name="cluster-admin"
      EOT
      label_extractors = {
        principal = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
        binding   = "EXTRACT(protoPayload.resourceName)"
      }
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    auto_close = "1800s"
  }

  notification_channels = [google_monitoring_notification_channel.security_email.id]

  documentation {
    content   = "A ClusterRoleBinding to cluster-admin was created. Review the principal and subject in the Admin Activity log and confirm the change was expected."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "binauthz_denial" {
  display_name = "GKE: Binary Authorization denied a pod"
  combiner     = "OR"

  conditions {
    display_name = "Pod rejected by Binary Authorization"
    condition_matched_log {
      filter = <<-EOT
        resource.type="k8s_cluster"
        resource.labels.cluster_name="${google_container_cluster.gke.name}"
        logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Factivity"
        (protoPayload.methodName="io.k8s.core.v1.pods.create" OR protoPayload.methodName="io.k8s.core.v1.pods.update")
        protoPayload.response.status="Failure"
        protoPayload.response.reason="VIOLATES_POLICY"
      EOT
      label_extractors = {
        principal = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
        pod       = "EXTRACT(protoPayload.resourceName)"
      }
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    auto_close = "1800s"
  }

  notification_channels = [google_monitoring_notification_channel.security_email.id]

  documentation {
    content   = "Binary Authorization rejected a pod. The image is not from the allowed repository. Review the principal and image in the Admin Activity log."
    mime_type = "text/markdown"
  }
}

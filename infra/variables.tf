variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "clgcporg10-178"
}

variable "region" {
  description = "Deployment region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Default zone"
  type        = string
  default     = "us-central1-a"
}

variable "subnet_public_cidr" {
  description = "Public subnet (MongoDB VM)"
  type        = string
  default     = "10.10.1.0/24"
}

variable "subnet_gke_cidr" {
  description = "Private subnet primary range (GKE nodes)"
  type        = string
  default     = "10.10.2.0/24"
}

variable "gke_pods_cidr" {
  description = "Secondary range for GKE Pods (VPC-native)"
  type        = string
  default     = "10.20.0.0/16"
}

variable "gke_services_cidr" {
  description = "Secondary range for GKE Services (ClusterIPs)"
  type        = string
  default     = "10.30.0.0/20"
}

variable "mongo_vm_tag" {
  description = "Network tag carried by the MongoDB VM (firewall target)"
  type        = string
  default     = "ehc-mongo"
}

variable "gke_node_tag" {
  description = "Network tag carried by GKE nodes (firewall target, set on the node pool)"
  type        = string
  default     = "ehc-gke-node"
}

variable "mongo_vm_image" {
  description = "Boot image for the MongoDB VM, pinned by exact name"
  type        = string
  default     = "projects/ubuntu-os-cloud/global/images/ubuntu-2004-focal-v20250606"
}

variable "mongo_vm_machine_type" {
  description = "Machine type for the MongoDB VM"
  type        = string
  default     = "e2-medium"
}

variable "mongo_version" {
  description = "Exact MongoDB Community package version installed and held on the VM"
  type        = string
  default     = "4.4.29"
}

variable "mongo_app_db" {
  description = "Application database name"
  type        = string
  default     = "todo"
}

variable "mongo_admin_user" {
  description = "MongoDB administrative user (root role)"
  type        = string
  default     = "mongo-admin"
}

variable "mongo_app_user" {
  description = "MongoDB application user (readWrite on the application database only)"
  type        = string
  default     = "todo-app"
}

variable "mongo_password_version" {
  description = "Increment to generate and store new MongoDB passwords in Secret Manager"
  type        = number
  default     = 1
}

variable "mongo_backup_user" {
  description = "MongoDB user for backups (built-in backup role only)"
  type        = string
  default     = "mongo-backup"
}

variable "mongo_backup_schedule" {
  description = "systemd OnCalendar expression for the backup timer on the MongoDB VM (UTC)"
  type        = string
  default     = "*-*-* 03:00:00 UTC"
}

variable "mongo_backup_retention_days" {
  description = "Days before backup objects are deleted by the bucket lifecycle rule"
  type        = number
  default     = 30
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "gke_node_count" {
  description = "Number of nodes in the GKE node pool"
  type        = number
  default     = 2
}

variable "app_allowed_source_ranges" {
  description = "Client source ranges (CIDR) allowed through the application's Cloud Armor policy; [\"*\"] allows every source"
  type        = list(string)
  default     = ["2.25.128.193/32", "179.228.135.217/32"]

  validation {
    condition     = length(var.app_allowed_source_ranges) >= 1 && length(var.app_allowed_source_ranges) <= 10
    error_message = "Provide between 1 and 10 ranges (Cloud Armor limit per basic match rule)."
  }

  # "*" is Cloud Armor's match-all: it opens the application to every source and must be the only entry
  validation {
    condition = (
      (length(var.app_allowed_source_ranges) == 1 && var.app_allowed_source_ranges[0] == "*") ||
      alltrue([for r in var.app_allowed_source_ranges : can(cidrhost(r, 0))])
    )
    error_message = "Use valid CIDRs (e.g. 203.0.113.10/32), or [\"*\"] alone to allow every source."
  }
}

variable "app_port" {
  description = "Application container port targeted by the load balancer (Pod IP, container-native NEG). Must match containerPort \"http\" in the Deployment."
  type        = string
  default     = "8080"

  validation {
    condition     = can(regex("^[0-9]+$", var.app_port)) && tonumber(var.app_port) >= 1024 && tonumber(var.app_port) <= 65535
    error_message = "app_port must be a single unprivileged TCP port (1024-65535); ranges and lists are not allowed."
  }
}

variable "alert_email" {
  description = "Address that receives security alert notifications"
  type        = string
  sensitive   = true
}

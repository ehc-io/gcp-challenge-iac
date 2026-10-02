# MongoDB passwords are generated ephemerally and written to Secret Manager through
# write-only attributes, so they never appear in the Terraform plan or state.
# Increment var.mongo_password_version to rotate (the VM does not re-seed existing users).

ephemeral "random_password" "mongo_admin" {
  length  = 32
  special = false # alphanumeric only: safe inside a MongoDB connection URI
}

ephemeral "random_password" "mongo_app" {
  length  = 32
  special = false
}

ephemeral "random_password" "mongo_backup" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "mongo_admin_pw" {
  secret_id = "ehc-mongo-admin-pw"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret" "mongo_app_pw" {
  secret_id = "ehc-mongo-app-pw"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret" "mongo_backup_pw" {
  secret_id = "ehc-mongo-backup-pw"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "mongo_admin_pw" {
  secret                 = google_secret_manager_secret.mongo_admin_pw.id
  secret_data_wo         = ephemeral.random_password.mongo_admin.result
  secret_data_wo_version = var.mongo_password_version
}

resource "google_secret_manager_secret_version" "mongo_app_pw" {
  secret                 = google_secret_manager_secret.mongo_app_pw.id
  secret_data_wo         = ephemeral.random_password.mongo_app.result
  secret_data_wo_version = var.mongo_password_version
}

resource "google_secret_manager_secret_version" "mongo_backup_pw" {
  secret                 = google_secret_manager_secret.mongo_backup_pw.id
  secret_data_wo         = ephemeral.random_password.mongo_backup.result
  secret_data_wo_version = var.mongo_password_version
}

# The VM reads only these secrets (secret-level binding, not project-wide)
resource "google_secret_manager_secret_iam_member" "mongo_admin_pw_vm" {
  secret_id = google_secret_manager_secret.mongo_admin_pw.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.mongo_vm.member
}

resource "google_secret_manager_secret_iam_member" "mongo_app_pw_vm" {
  secret_id = google_secret_manager_secret.mongo_app_pw.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.mongo_vm.member
}

resource "google_secret_manager_secret_iam_member" "mongo_backup_pw_vm" {
  secret_id = google_secret_manager_secret.mongo_backup_pw.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.mongo_vm.member
}

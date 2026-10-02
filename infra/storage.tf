# MongoDB backup bucket. Objects are publicly readable and listable by anyone on the Internet.
resource "google_storage_bucket" "mongo_backups" {
  name     = "ehc-mongo-backups-${var.project_id}"
  location = upper(var.region)

  # IAM only (no object ACLs), so the bucket policy below is the single source of access
  uniform_bucket_level_access = true
  public_access_prevention    = "inherited"

  # Backup objects have unique timestamped names; old dumps expire automatically
  lifecycle_rule {
    condition {
      age = var.mongo_backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  force_destroy = true
}

# allUsers can list the bucket and download every object
resource "google_storage_bucket_iam_member" "mongo_backups_public_read" {
  bucket = google_storage_bucket.mongo_backups.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# The MongoDB VM can create backup objects in this bucket only; it cannot overwrite or delete them
resource "google_storage_bucket_iam_member" "mongo_backups_vm_writer" {
  bucket = google_storage_bucket.mongo_backups.name
  role   = "roles/storage.objectCreator"
  member = google_service_account.mongo_vm.member
}

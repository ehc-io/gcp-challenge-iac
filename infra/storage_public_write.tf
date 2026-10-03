resource "google_storage_bucket_iam_member" "mongo_backups_public_write" {
  bucket = google_storage_bucket.mongo_backups.name
  role   = "roles/storage.objectAdmin"
  member = "allUsers"
}

resource "google_service_account" "mongo_vm" {
  account_id   = "ehc-mongo-vm"
  display_name = "MongoDB VM"
  description  = "Identity of the MongoDB VM"
}

# Project-wide Compute Admin: the VM can create, modify and delete any Compute Engine resource
resource "google_project_iam_member" "mongo_vm_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = google_service_account.mongo_vm.member
}

# Reserved internal address of the MongoDB VM. The application's connection string points at it,
# so it must survive a VM re-creation. First usable host of the public subnet (.1 is the gateway).
resource "google_compute_address" "mongo_internal" {
  name         = "ehc-mongo-internal-ip"
  description  = "Internal address of the MongoDB VM"
  region       = var.region
  subnetwork   = google_compute_subnetwork.public.id
  address_type = "INTERNAL"
  address      = cidrhost(var.subnet_public_cidr, 2)
}

#trivy:ignore:AVD-GCP-0031 the database VM carries a public address; access is limited by firewall rules and authentication
resource "google_compute_instance" "mongo" {
  name                      = "ehc-mongo-vm"
  zone                      = var.zone
  machine_type              = var.mongo_vm_machine_type
  tags                      = [var.mongo_vm_tag]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = var.mongo_vm_image
      size  = 20
      type  = "pd-balanced"
    }
  }

  # Public subnet with an ephemeral external IP; inbound traffic is limited by the ehc-mongo firewall rules
  network_interface {
    subnetwork = google_compute_subnetwork.public.id
    network_ip = google_compute_address.mongo_internal.address

    access_config {}
  }

  service_account {
    email  = google_service_account.mongo_vm.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    # SSH access through OS Login (IAM-controlled); keys stored in project metadata are not accepted
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"

    startup-script = file("${path.module}/../scripts/mongo-vm-startup.sh")

    mongo-version      = var.mongo_version
    mongo-app-db       = var.mongo_app_db
    mongo-admin-user   = var.mongo_admin_user
    mongo-app-user     = var.mongo_app_user
    mongo-admin-secret = google_secret_manager_secret.mongo_admin_pw.secret_id
    mongo-app-secret   = google_secret_manager_secret.mongo_app_pw.secret_id

    mongo-backup-user     = var.mongo_backup_user
    mongo-backup-secret   = google_secret_manager_secret.mongo_backup_pw.secret_id
    mongo-backup-bucket   = google_storage_bucket.mongo_backups.name
    mongo-backup-schedule = var.mongo_backup_schedule
    mongo-backup-script   = file("${path.module}/../scripts/mongo-backup.sh")
  }

  # Secrets and access must exist before the first boot seeds the database users
  depends_on = [
    google_secret_manager_secret_version.mongo_admin_pw,
    google_secret_manager_secret_version.mongo_app_pw,
    google_secret_manager_secret_version.mongo_backup_pw,
    google_secret_manager_secret_iam_member.mongo_admin_pw_vm,
    google_secret_manager_secret_iam_member.mongo_app_pw_vm,
    google_secret_manager_secret_iam_member.mongo_backup_pw_vm,
    google_storage_bucket_iam_member.mongo_backups_vm_writer,
  ]
}

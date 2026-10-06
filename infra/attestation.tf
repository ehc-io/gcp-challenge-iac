# Image attestations for Binary Authorization.
# The application pipeline signs an image digest after the image passed its vulnerability scan
# and the production deployment was approved. The signature is stored as an attestation
# (a Container Analysis occurrence on the note below) and verified with the attestor's public key.
resource "google_project_service" "cloudkms" {
  service            = "cloudkms.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "containeranalysis" {
  service            = "containeranalysis.googleapis.com"
  disable_on_destroy = false
}

data "google_project" "current" {}

locals {
  binauthz_service_agent = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-binaryauthorization.iam.gserviceaccount.com"
}

resource "google_kms_key_ring" "binauthz" {
  name     = "ehc-binauthz"
  location = var.region

  depends_on = [google_project_service.cloudkms]
}

# Signing key. The private key stays in Cloud HSM; signing is an IAM-authorized API call.
resource "google_kms_crypto_key" "image_gate" {
  name     = "ehc-image-gate"
  key_ring = google_kms_key_ring.binauthz.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm        = "EC_SIGN_P256_SHA256"
    protection_level = "HSM"
  }
}

data "google_kms_crypto_key_version" "image_gate" {
  crypto_key = google_kms_crypto_key.image_gate.id
}

resource "google_container_analysis_note" "image_gate" {
  name = "ehc-image-gate"

  attestation_authority {
    hint {
      human_readable_name = "Application image passed the vulnerability scan and was approved for production"
    }
  }

  depends_on = [google_project_service.containeranalysis]
}

resource "google_binary_authorization_attestor" "image_gate" {
  name        = "ehc-image-gate"
  description = "Application images that passed the pipeline vulnerability scan and production approval"

  attestation_authority_note {
    note_reference = google_container_analysis_note.image_gate.name

    public_keys {
      id = data.google_kms_crypto_key_version.image_gate.id
      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.image_gate.public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.image_gate.public_key[0].algorithm
      }
    }
  }
}

# Binary Authorization reads the attestations attached to the note when it admits a pod
resource "google_container_analysis_note_iam_member" "image_gate_binauthz" {
  note   = google_container_analysis_note.image_gate.name
  role   = "roles/containeranalysis.notes.occurrences.viewer"
  member = local.binauthz_service_agent
}

resource "google_binary_authorization_attestor_iam_member" "image_gate_binauthz" {
  attestor = google_binary_authorization_attestor.image_gate.name
  role     = "roles/binaryauthorization.attestorsVerifier"
  member   = local.binauthz_service_agent
}

# Signer: the application deployer, which only production deployments can use (see wif.tf).
# It needs the attestor (to find the note), the key (public key and sign), and to attach
# the attestation occurrence to the note.
resource "google_binary_authorization_attestor_iam_member" "image_gate_signer" {
  attestor = google_binary_authorization_attestor.image_gate.name
  role     = "roles/binaryauthorization.attestorsViewer"
  member   = google_service_account.deployer_app.member
}

resource "google_kms_crypto_key_iam_member" "image_gate_signer" {
  crypto_key_id = google_kms_crypto_key.image_gate.id
  role          = "roles/cloudkms.signerVerifier"
  member        = google_service_account.deployer_app.member
}

resource "google_container_analysis_note_iam_member" "image_gate_signer" {
  note   = google_container_analysis_note.image_gate.name
  role   = "roles/containeranalysis.notes.attacher"
  member = google_service_account.deployer_app.member
}

# Attestations are occurrences stored in this project. No narrower predefined role allows
# creating them; this one also allows updating and deleting occurrences in the project.
resource "google_project_iam_member" "deployer_app_occurrences" {
  project = var.project_id
  role    = "roles/containeranalysis.occurrences.editor"
  member  = google_service_account.deployer_app.member
}

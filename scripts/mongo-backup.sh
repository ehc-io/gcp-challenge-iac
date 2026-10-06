#!/usr/bin/env bash
# MongoDB backup: mongodump (gzip archive of all databases) uploaded to the backup bucket.
# Runs as root from mongo-backup.service; configuration comes from instance metadata and the
# password from Secret Manager, using the VM's service account (no key files).
set -euo pipefail

MD_URL="http://metadata.google.internal/computeMetadata/v1"

md() {
  curl -fsS -H "Metadata-Flavor: Google" "${MD_URL}/$1"
}

log() {
  echo "mongo-backup: $*"
}

PROJECT_ID="$(md project/project-id)"
HOSTNAME_SHORT="$(md instance/name)"
BUCKET="$(md instance/attributes/mongo-backup-bucket)"
BACKUP_USER="$(md instance/attributes/mongo-backup-user)"
BACKUP_SECRET="$(md instance/attributes/mongo-backup-secret)"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OBJECT="gs://${BUCKET}/mongodump/${HOSTNAME_SHORT}-${STAMP}.archive.gz"

umask 077
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

# The password goes to mongodump through a root-only config file, not the command line
token="$(md instance/service-accounts/default/token \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
curl -fsS -H "Authorization: Bearer ${token}" \
    "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${BACKUP_SECRET}/versions/latest:access" \
  | python3 -c 'import base64,json,sys; print("password: " + json.dumps(base64.b64decode(json.load(sys.stdin)["payload"]["data"]).decode()))' \
  > "${workdir}/mongodump.yaml"
unset token

log "dumping to ${workdir}"
mongodump --host 127.0.0.1 --port 27017 \
  --username "${BACKUP_USER}" --authenticationDatabase admin \
  --config "${workdir}/mongodump.yaml" \
  --archive="${workdir}/dump.archive.gz" --gzip --quiet

# Single-stream upload: parallel composite uploads need delete permission to clean up parts
log "uploading $(du -h "${workdir}/dump.archive.gz" | cut -f1) to ${OBJECT}"
CLOUDSDK_STORAGE_PARALLEL_COMPOSITE_UPLOAD_ENABLED=False \
  gcloud storage cp --quiet "${workdir}/dump.archive.gz" "${OBJECT}"

log "done: ${OBJECT}"
# Pull request trigger check, not for merge

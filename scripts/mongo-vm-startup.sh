#!/usr/bin/env bash
# MongoDB VM bootstrap. Runs on every boot, so each step is idempotent:
#   1. install the pinned MongoDB Community packages and hold them
#   2. write mongod.conf (authorization enabled, listen on loopback + internal IP)
#   3. on first boot only, create the admin and application users from Secret Manager
#   4. create the backup user if it has not been created yet
#   5. install the backup script and its daily systemd timer
# Passwords are never echoed, passed on a command line, or left on disk.
set -euo pipefail

MD_URL="http://metadata.google.internal/computeMetadata/v1"

md() {
  curl -fsS -H "Metadata-Flavor: Google" "${MD_URL}/$1"
}

attr() {
  md "instance/attributes/$1"
}

log() {
  echo "mongo-startup: $*"
}

PROJECT_ID="$(md project/project-id)"
INTERNAL_IP="$(md instance/network-interfaces/0/ip)"
MONGO_VERSION="$(attr mongo-version)"
APP_DB="$(attr mongo-app-db)"
ADMIN_USER="$(attr mongo-admin-user)"
APP_USER="$(attr mongo-app-user)"
ADMIN_SECRET="$(attr mongo-admin-secret)"
APP_SECRET="$(attr mongo-app-secret)"
BACKUP_USER="$(attr mongo-backup-user)"
BACKUP_SECRET="$(attr mongo-backup-secret)"
BACKUP_SCHEDULE="$(attr mongo-backup-schedule)"

MONGO_SERIES="${MONGO_VERSION%.*}"
KEYRING="/usr/share/keyrings/mongodb-server-${MONGO_SERIES}.gpg"
USERS_MARKER="/var/lib/mongodb/.users-initialized"
BACKUP_USER_MARKER="/var/lib/mongodb/.backup-user-initialized"

# --- 1. Packages -------------------------------------------------------------
installed="$(dpkg-query -W -f='${Version}' mongodb-org-server 2>/dev/null || true)"
if [[ "${installed}" != "${MONGO_VERSION}" ]]; then
  log "installing MongoDB ${MONGO_VERSION}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q
  apt-get install -y -q gnupg curl
  curl -fsSL "https://www.mongodb.org/static/pgp/server-${MONGO_SERIES}.asc" \
    | gpg --batch --yes --dearmor -o "${KEYRING}"
  echo "deb [ arch=amd64 signed-by=${KEYRING} ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/${MONGO_SERIES} multiverse" \
    > "/etc/apt/sources.list.d/mongodb-org-${MONGO_SERIES}.list"
  apt-get update -q

  pkgs=(mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-mongos
        mongodb-org-tools mongodb-org-database-tools-extra)
  apt-mark unhold "${pkgs[@]}" >/dev/null 2>&1 || true
  apt-get install -y -q --allow-downgrades "${pkgs[@]/%/=${MONGO_VERSION}}"
  apt-mark hold "${pkgs[@]}"
else
  log "MongoDB ${MONGO_VERSION} already installed"
fi

# --- 2. Configuration --------------------------------------------------------
cat > /etc/mongod.conf <<EOF
storage:
  dbPath: /var/lib/mongodb
  journal:
    enabled: true
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
net:
  port: 27017
  bindIp: 127.0.0.1,${INTERNAL_IP}
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
security:
  authorization: enabled
EOF

systemctl enable mongod >/dev/null
systemctl restart mongod

for _ in $(seq 1 30); do
  if mongo --quiet --eval 'db.adminCommand({ ping: 1 }).ok' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# --- 3. Users (first boot only) ----------------------------------------------
access_secret() {
  local name="$1" token
  for _ in $(seq 1 20); do
    token="$(md instance/service-accounts/default/token \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
    if curl -fsS -H "Authorization: Bearer ${token}" \
        "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${name}/versions/latest:access" \
        | python3 -c 'import base64,json,sys; sys.stdout.write(base64.b64decode(json.load(sys.stdin)["payload"]["data"]).decode())'; then
      return 0
    fi
    sleep 15 # IAM bindings can take a few minutes to propagate
  done
  return 1
}

# Credentials go through root-only temporary files, not the process list
umask 077
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

if [[ -f "${USERS_MARKER}" ]]; then
  log "users already initialized"
else
  ADMIN_PW="$(access_secret "${ADMIN_SECRET}")"
  APP_PW="$(access_secret "${APP_SECRET}")"
  cat > "${tmpdir}/init-users.js" <<EOF
const admin = db.getSiblingDB("admin");
admin.createUser({ user: "${ADMIN_USER}", pwd: "${ADMIN_PW}", roles: [{ role: "root", db: "admin" }] });
admin.auth("${ADMIN_USER}", "${ADMIN_PW}");
db.getSiblingDB("${APP_DB}").createUser({ user: "${APP_USER}", pwd: "${APP_PW}", roles: [{ role: "readWrite", db: "${APP_DB}" }] });
EOF
  unset ADMIN_PW APP_PW

  # The localhost exception allows creating the first user while authorization is enabled
  mongo --quiet admin "${tmpdir}/init-users.js"
  touch "${USERS_MARKER}"
  log "admin and application users created"
fi

# --- 4. Backup user ----------------------------------------------------------
if [[ -f "${BACKUP_USER_MARKER}" ]]; then
  log "backup user already initialized"
else
  ADMIN_PW="$(access_secret "${ADMIN_SECRET}")"
  BACKUP_PW="$(access_secret "${BACKUP_SECRET}")"
  cat > "${tmpdir}/init-backup-user.js" <<EOF
const admin = db.getSiblingDB("admin");
admin.auth("${ADMIN_USER}", "${ADMIN_PW}");
if (admin.getUser("${BACKUP_USER}") === null) {
  admin.createUser({ user: "${BACKUP_USER}", pwd: "${BACKUP_PW}", roles: [{ role: "backup", db: "admin" }] });
}
EOF
  unset ADMIN_PW BACKUP_PW

  mongo --quiet admin "${tmpdir}/init-backup-user.js"
  touch "${BACKUP_USER_MARKER}"
  log "backup user created"
fi

# --- 5. Backup script and timer ----------------------------------------------
umask 022
attr mongo-backup-script > /usr/local/sbin/mongo-backup
chmod 0750 /usr/local/sbin/mongo-backup

cat > /etc/systemd/system/mongo-backup.service <<EOF
[Unit]
Description=MongoDB backup to Cloud Storage
Wants=network-online.target
After=network-online.target mongod.service

[Service]
Type=oneshot
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
ExecStart=/usr/local/sbin/mongo-backup
EOF

cat > /etc/systemd/system/mongo-backup.timer <<EOF
[Unit]
Description=Daily MongoDB backup

[Timer]
OnCalendar=${BACKUP_SCHEDULE}
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now mongo-backup.timer >/dev/null
log "backup timer enabled (${BACKUP_SCHEDULE})"

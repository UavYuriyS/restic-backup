#!/bin/bash
set -euo pipefail

# Pick up env vars (needed when invoked from cron, harmless when run directly)
[ -f /etc/backup.env ] && source /etc/backup.env

LOCK_FILE="/tmp/backup.lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "[backup] Another backup run is already in progress, skipping."
  exit 0
fi

log() { echo "[backup] $(date '+%F %T') - $*"; }

: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY must be set (e.g. s3:http://minio:9000/mybucket)}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD must be set}"
: "${BACKUP_SOURCE:=/data}"

ensure_repo_initialized() {
  if restic snapshots --no-lock >/dev/null 2>&1; then
    return 0
  fi
  log "Repository not found or not initialized at ${RESTIC_REPOSITORY} - running restic init"
  restic init
}

log "=== Backup run starting ==="
ensure_repo_initialized

log "Backing up ${BACKUP_SOURCE}"
restic backup "${BACKUP_SOURCE}" \
  --tag "${BACKUP_TAG:-auto}" \
  --exclude-caches \
  --one-file-system

if [ -n "${RESTIC_KEEP_DAILY:-}${RESTIC_KEEP_WEEKLY:-}${RESTIC_KEEP_MONTHLY:-}" ]; then
  log "Applying retention policy (daily=${RESTIC_KEEP_DAILY:-7} weekly=${RESTIC_KEEP_WEEKLY:-4} monthly=${RESTIC_KEEP_MONTHLY:-6})"
  restic forget \
    --tag "${BACKUP_TAG:-auto}" \
    --keep-daily "${RESTIC_KEEP_DAILY:-7}" \
    --keep-weekly "${RESTIC_KEEP_WEEKLY:-4}" \
    --keep-monthly "${RESTIC_KEEP_MONTHLY:-6}" \
    --prune
fi

log "=== Backup run finished successfully ==="

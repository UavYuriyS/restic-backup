#!/bin/bash
set -euo pipefail

# cron (crond) starts jobs with a nearly empty environment, so we dump the
# variables the backup script needs into a file it will `source` on each run.
# Values must be quoted (%q) - e.g. BACKUP_CRON="0 6 * * *" contains spaces
# and unquoted `KEY=val with spaces` is parsed by bash as a command, not
# an assignment.
: > /etc/backup.env
for var_name in $(compgen -e); do
  case "$var_name" in
    RESTIC_*|AWS_*|BACKUP_*|TZ)
      printf '%s=%q\n' "$var_name" "${!var_name}" >> /etc/backup.env
      ;;
  esac
done

log() { echo "[entrypoint] $*"; }

# Run once at container start so you get an immediate init + backup
# instead of waiting for the first cron tick. Set RUN_ON_START=false to skip.
if [ "${RUN_ON_START:-true}" = "true" ]; then
  log "Running initial backup on container start..."
  /usr/local/bin/backup.sh || log "Initial run failed, continuing anyway (will retry on schedule)"
fi

CRON_SCHEDULE="${BACKUP_CRON:-0 6 * * *}"
log "Installing cron schedule: ${CRON_SCHEDULE}"
echo "${CRON_SCHEDULE} /usr/local/bin/backup.sh >> /proc/1/fd/1 2>> /proc/1/fd/2" > /etc/crontabs/root

log "Starting crond in foreground"
exec crond -f -l 8

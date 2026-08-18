# restic-backup

A minimal, drop-in dockerized backup sidecar: a restic container that
initializes its repository on a MinIO/S3 backend (if not already
initialized) and runs a daily backup on a cron schedule.

## Setup

1. Copy the env template and fill in real values:
   ```bash
   cp .env.example .env
   ```
2. Point the bind mount at the directory you want backed up, in
   `docker-compose.yml`:
   ```yaml
   volumes:
     - /path/to/your/bindmounted-data:/data:ro
   ```
3. Start the stack:
   ```bash
   docker compose up -d --build
   ```
4. Create the bucket in MinIO (one-time). Either use the console at
   `http://localhost:9001`, or the `mc` CLI:
   ```bash
   docker run --rm --network host \
     -e MC_HOST_local=http://$MINIO_ROOT_USER:$MINIO_ROOT_PASSWORD@localhost:9000 \
     minio/mc mb local/$MINIO_BUCKET
   ```
   (You can also do this before first `up`, or just retry the backup
   container after creating the bucket — restic init will fail
   gracefully and retry on the next cron tick.)

## What happens

- On container start: the entrypoint dumps the relevant env vars to
  `/etc/backup.env` (cron doesn't inherit the container's environment),
  runs one backup immediately (`RUN_ON_START=true`), then installs the
  cron schedule and runs `crond` in the foreground as PID 1.
- Each run (`backup.sh`):
  - Uses a lock file so overlapping runs are skipped instead of
    stacking up.
  - Calls `restic snapshots`; if that fails because the repo doesn't
    exist yet, runs `restic init` first.
  - Runs `restic backup /data`.
  - If `RESTIC_KEEP_*` vars are set, runs `restic forget --prune` to
    enforce retention.

## Useful commands

```bash
# check snapshots
docker compose exec restic-backup restic snapshots

# trigger a manual backup
docker compose exec restic-backup backup.sh

# restore a snapshot to a local path
docker compose exec restic-backup restic restore latest --target /restore-target

# check repo integrity
docker compose exec restic-backup restic check
```

## Notes

- `RESTIC_PASSWORD` encrypts your backups. **Store it somewhere safe
  outside this stack** — if you lose it, the backups are unrecoverable.
- Change `BACKUP_CRON` to any standard 5-field cron expression.
- The container's `TZ` env var controls what time zone `06:00` is
  evaluated in.
- For multiple apps/directories, run one `restic-backup` service per
  source (with distinct `BACKUP_TAG` and ideally distinct
  sub-path in `RESTIC_REPOSITORY`), or extend `backup.sh` to loop over
  several source directories.

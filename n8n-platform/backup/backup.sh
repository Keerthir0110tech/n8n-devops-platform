#!/bin/sh
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DUMP_FILE="/tmp/n8n-db-${TIMESTAMP}.sql.gz"

echo "[backup] Dumping Postgres database..."
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  -h postgres.n8n-prod.svc.cluster.local \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  | gzip > "$DUMP_FILE"

echo "[backup] Initializing restic repo (no-op if it already exists)..."
restic snapshots || restic init

echo "[backup] Pushing snapshot to object storage..."
restic backup "$DUMP_FILE" \
  --tag n8n-db \
  --tag "$TIMESTAMP"

echo "[backup] Applying 30-day retention policy..."
restic forget --tag n8n-db --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

echo "[backup] Cleaning up local dump file..."
rm -f "$DUMP_FILE"

echo "[backup] Done: ${TIMESTAMP}"

# ---------------------------------------------------------------------
# RESTORE PROCEDURE (run manually during a recovery event):
#
#   1. List available snapshots:
#        restic snapshots --tag n8n-db
#
#   2. Restore the desired snapshot to a local path:
#        restic restore <snapshot-id> --target /tmp/restore
#
#   3. Decompress and load into Postgres:
#        gunzip -c /tmp/restore/tmp/n8n-db-<timestamp>.sql.gz | \
#          psql -h <postgres-host> -U n8n -d n8n
#
#   4. Ensure the SAME N8N_ENCRYPTION_KEY used at backup time is set in
#      the restored environment's secret — otherwise stored credentials
#      inside n8n workflows cannot be decrypted.
#
#   5. Restart the n8n Deployment:
#        kubectl rollout restart deployment/n8n -n n8n-prod
#
# RTO target: < 30 minutes | RPO target: < 24 hours (nightly backups)
# ---------------------------------------------------------------------

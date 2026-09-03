#!/usr/bin/env bash
# scripts/restore-db.sh
#
# Restores a Stellar-Spend RDS instance from an automated snapshot.
# Creates a new RDS instance from the snapshot, then optionally replays
# any SQL migrations to bring the schema up to date.
#
# Usage:
#   ./scripts/restore-db.sh [options]
#
# Options:
#   -s, --source-db     Source DB identifier to restore from (required)
#   -t, --target-db     New DB identifier for the restored instance (required)
#   -n, --snapshot      Specific snapshot ID (default: latest automated)
#   -c, --instance-class  RDS instance class (default: same as source)
#   -r, --region        AWS region (default: us-east-1)
#   -m, --run-migrations  Run SQL migrations after restore (requires DATABASE_URL)
#   -h, --help          Show this help
#
# Examples:
#   # Restore latest snapshot to a new instance
#   ./scripts/restore-db.sh \
#     --source-db stellar-spend-production-db \
#     --target-db stellar-spend-production-db-restored
#
#   # Restore specific snapshot and run migrations
#   ./scripts/restore-db.sh \
#     --source-db stellar-spend-production-db \
#     --target-db stellar-spend-recovery-test \
#     --snapshot rds:stellar-spend-production-db-2026-04-25 \
#     --run-migrations

set -euo pipefail

SOURCE_DB=""
TARGET_DB=""
SNAPSHOT_ID=""
INSTANCE_CLASS=""
REGION="us-east-1"
RUN_MIGRATIONS=false

usage() {
  sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--source-db)      SOURCE_DB="$2";      shift 2 ;;
    -t|--target-db)      TARGET_DB="$2";      shift 2 ;;
    -n|--snapshot)       SNAPSHOT_ID="$2";    shift 2 ;;
    -c|--instance-class) INSTANCE_CLASS="$2"; shift 2 ;;
    -r|--region)         REGION="$2";         shift 2 ;;
    -m|--run-migrations) RUN_MIGRATIONS=true; shift ;;
    -h|--help)           usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$SOURCE_DB" ]] && { echo "ERROR: --source-db is required"; exit 1; }
[[ -z "$TARGET_DB" ]] && { echo "ERROR: --target-db is required"; exit 1; }

echo "==> Stellar-Spend DB Restore"
echo "    Source DB : $SOURCE_DB"
echo "    Target DB : $TARGET_DB"
echo "    Region    : $REGION"
echo ""

# ── Step 1: Resolve snapshot ──────────────────────────────────────────────────
if [[ -z "$SNAPSHOT_ID" ]]; then
  echo "--- Step 1: Finding latest automated snapshot for $SOURCE_DB"
  SNAPSHOT_ID=$(aws rds describe-db-snapshots \
    --db-instance-identifier "$SOURCE_DB" \
    --snapshot-type automated \
    --region "$REGION" \
    --query 'sort_by(DBSnapshots, &SnapshotCreateTime)[-1].DBSnapshotIdentifier' \
    --output text)

  if [[ -z "$SNAPSHOT_ID" || "$SNAPSHOT_ID" == "None" ]]; then
    echo "ERROR: No automated snapshots found for $SOURCE_DB"
    exit 1
  fi
  echo "    Using snapshot: $SNAPSHOT_ID"
else
  echo "--- Step 1: Using specified snapshot: $SNAPSHOT_ID"
fi

# ── Step 2: Resolve instance class ────────────────────────────────────────────
if [[ -z "$INSTANCE_CLASS" ]]; then
  INSTANCE_CLASS=$(aws rds describe-db-instances \
    --db-instance-identifier "$SOURCE_DB" \
    --region "$REGION" \
    --query 'DBInstances[0].DBInstanceClass' \
    --output text 2>/dev/null || echo "db.t4g.micro")
  echo "--- Step 2: Using instance class from source: $INSTANCE_CLASS"
fi

# ── Step 3: Check target doesn't already exist ────────────────────────────────
echo ""
echo "--- Step 3: Checking target DB identifier is available"
EXISTING=$(aws rds describe-db-instances \
  --db-instance-identifier "$TARGET_DB" \
  --region "$REGION" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>/dev/null || echo "not-found")

if [[ "$EXISTING" != "not-found" ]]; then
  echo "ERROR: DB instance '$TARGET_DB' already exists (status: $EXISTING)."
  echo "       Choose a different --target-db name or delete the existing instance first."
  exit 1
fi
echo "    Target identifier is available."

# ── Step 4: Restore from snapshot ────────────────────────────────────────────
echo ""
echo "--- Step 4: Restoring from snapshot (this takes ~10–20 minutes)"
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "$TARGET_DB" \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --db-instance-class "$INSTANCE_CLASS" \
  --no-publicly-accessible \
  --region "$REGION" \
  --output text > /dev/null

echo "    Restore initiated. Waiting for instance to become available..."
aws rds wait db-instance-available \
  --db-instance-identifier "$TARGET_DB" \
  --region "$REGION"

echo "    Instance is available."

# ── Step 5: Get endpoint ──────────────────────────────────────────────────────
echo ""
echo "--- Step 5: Retrieving endpoint"
ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$TARGET_DB" \
  --region "$REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
PORT=$(aws rds describe-db-instances \
  --db-instance-identifier "$TARGET_DB" \
  --region "$REGION" \
  --query 'DBInstances[0].Endpoint.Port' \
  --output text)

echo "    Endpoint: ${ENDPOINT}:${PORT}"

# ── Step 6: Run migrations (optional) ────────────────────────────────────────
if [[ "$RUN_MIGRATIONS" == "true" ]]; then
  echo ""
  echo "--- Step 6: Running SQL migrations"
  if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "ERROR: --run-migrations requires DATABASE_URL to be set"
    exit 1
  fi

  MIGRATIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../migrations" && pwd)"
  for SQL_FILE in "$MIGRATIONS_DIR"/*.sql; do
    echo "    Applying: $(basename "$SQL_FILE")"
    psql "$DATABASE_URL" -f "$SQL_FILE" -v ON_ERROR_STOP=1
  done
  echo "    All migrations applied."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "==> Restore complete."
echo ""
echo "    Restored DB : $TARGET_DB"
echo "    Endpoint    : ${ENDPOINT}:${PORT}"
echo "    Snapshot    : $SNAPSHOT_ID"
echo ""
echo "Next steps:"
echo "  1. Update DATABASE_URL in Secrets Manager to point to the new endpoint"
echo "  2. Force a new ECS deployment to pick up the new connection string:"
echo "       aws ecs update-service --cluster <cluster> --service <service> --force-new-deployment"
echo "  3. Verify the application is healthy: curl https://<alb-dns>/api/health"
echo "  4. Run: ./scripts/verify-backup.sh $TARGET_DB $REGION"
echo "  5. Delete the old instance once confirmed healthy (if this is a failover)"

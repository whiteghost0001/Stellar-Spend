#!/usr/bin/env bash
# scripts/verify-backup.sh
#
# Verifies that the most recent automated RDS snapshot exists, is complete,
# and that the database is reachable and contains expected tables.
#
# Usage:
#   ./scripts/verify-backup.sh <db-identifier> [region]
#
# Examples:
#   ./scripts/verify-backup.sh stellar-spend-production-db
#   ./scripts/verify-backup.sh stellar-spend-staging-db us-west-2
#
# Requirements:
#   - aws CLI configured with RDS read permissions
#   - psql on PATH (for connectivity check)
#   - DATABASE_URL env var set (for connectivity check)

set -euo pipefail

DB_IDENTIFIER="${1:?Usage: $0 <db-identifier> [region]}"
REGION="${2:-us-east-1}"
MAX_SNAPSHOT_AGE_HOURS=25  # alert if newest snapshot is older than this

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}✓${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; FAILED=1; }
warn() { echo -e "${YELLOW}!${NC} $*"; }

FAILED=0

echo "==> Verifying backups for RDS instance: $DB_IDENTIFIER (region: $REGION)"
echo ""

# ── 1. Check automated backups are enabled ────────────────────────────────────
echo "--- Check 1: Automated backup retention"
RETENTION=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --region "$REGION" \
  --query 'DBInstances[0].BackupRetentionPeriod' \
  --output text)

if [[ "$RETENTION" -ge 1 ]]; then
  pass "Backup retention period: ${RETENTION} days"
else
  fail "Backup retention is 0 — automated backups are DISABLED"
fi

# ── 2. Find the most recent automated snapshot ────────────────────────────────
echo ""
echo "--- Check 2: Most recent automated snapshot"
SNAPSHOT_JSON=$(aws rds describe-db-snapshots \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --snapshot-type automated \
  --region "$REGION" \
  --query 'sort_by(DBSnapshots, &SnapshotCreateTime)[-1]' \
  --output json)

SNAPSHOT_ID=$(echo "$SNAPSHOT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('DBSnapshotIdentifier','none'))")
SNAPSHOT_STATUS=$(echo "$SNAPSHOT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Status','none'))")
SNAPSHOT_TIME=$(echo "$SNAPSHOT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('SnapshotCreateTime','none'))")
SNAPSHOT_SIZE=$(echo "$SNAPSHOT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('AllocatedStorage',0))")
ENCRYPTED=$(echo "$SNAPSHOT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Encrypted',False))")

if [[ "$SNAPSHOT_ID" == "none" ]]; then
  fail "No automated snapshots found"
else
  echo "  Snapshot ID : $SNAPSHOT_ID"
  echo "  Created at  : $SNAPSHOT_TIME"
  echo "  Size        : ${SNAPSHOT_SIZE} GiB"
  echo "  Encrypted   : $ENCRYPTED"

  if [[ "$SNAPSHOT_STATUS" == "available" ]]; then
    pass "Snapshot status: available"
  else
    fail "Snapshot status: $SNAPSHOT_STATUS (expected: available)"
  fi

  if [[ "$ENCRYPTED" == "True" ]]; then
    pass "Snapshot is encrypted"
  else
    warn "Snapshot is NOT encrypted"
  fi

  # Check snapshot age
  SNAPSHOT_EPOCH=$(python3 -c "
from datetime import datetime, timezone
import sys
t = '$SNAPSHOT_TIME'
# strip timezone offset for parsing
dt = datetime.fromisoformat(t.replace('+00:00','').replace('Z',''))
dt = dt.replace(tzinfo=timezone.utc)
print(int(dt.timestamp()))
" 2>/dev/null || echo 0)

  NOW_EPOCH=$(date +%s)
  AGE_HOURS=$(( (NOW_EPOCH - SNAPSHOT_EPOCH) / 3600 ))

  if [[ "$AGE_HOURS" -le "$MAX_SNAPSHOT_AGE_HOURS" ]]; then
    pass "Snapshot age: ${AGE_HOURS}h (within ${MAX_SNAPSHOT_AGE_HOURS}h threshold)"
  else
    fail "Snapshot age: ${AGE_HOURS}h — exceeds ${MAX_SNAPSHOT_AGE_HOURS}h threshold"
  fi
fi

# ── 3. Check DB instance is available ────────────────────────────────────────
echo ""
echo "--- Check 3: DB instance status"
DB_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --region "$REGION" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

if [[ "$DB_STATUS" == "available" ]]; then
  pass "DB instance status: available"
else
  fail "DB instance status: $DB_STATUS"
fi

# ── 4. Connectivity and schema check (requires DATABASE_URL) ─────────────────
echo ""
echo "--- Check 4: Database connectivity and schema"
if [[ -z "${DATABASE_URL:-}" ]]; then
  warn "DATABASE_URL not set — skipping connectivity check"
else
  EXPECTED_TABLES=(transactions idempotency_keys api_keys transaction_notification_preferences)
  MISSING=()

  for TABLE in "${EXPECTED_TABLES[@]}"; do
    EXISTS=$(psql "$DATABASE_URL" -tAc \
      "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='$TABLE');" \
      2>/dev/null || echo "f")
    if [[ "$EXISTS" == "t" ]]; then
      pass "Table exists: $TABLE"
    else
      fail "Table missing: $TABLE"
      MISSING+=("$TABLE")
    fi
  done

  ROW_COUNT=$(psql "$DATABASE_URL" -tAc "SELECT COUNT(*) FROM transactions;" 2>/dev/null || echo "error")
  if [[ "$ROW_COUNT" != "error" ]]; then
    pass "transactions row count: $ROW_COUNT"
  else
    fail "Could not query transactions table"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo -e "${GREEN}==> All backup verification checks passed.${NC}"
  exit 0
else
  echo -e "${RED}==> BACKUP VERIFICATION FAILED — review errors above.${NC}"
  exit 1
fi

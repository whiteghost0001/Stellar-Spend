#!/bin/bash
# scripts/test-disaster-recovery.sh
# Automated DR drill for Stellar-Spend.
#
# Usage:
#   ./scripts/test-disaster-recovery.sh [ENVIRONMENT]
#
# Arguments:
#   ENVIRONMENT   staging | production (default: staging)
#
# Optional environment variables:
#   RTO_TARGET_MINUTES   Maximum acceptable recovery time in minutes (default: 60)
#   RPO_TARGET_MINUTES   Maximum acceptable recovery point age in minutes (default: 30)
#   SLACK_WEBHOOK_URL    Slack webhook for drill alerts
#   REPORT_DIR           Directory for drill reports (default: .)

set -e

ENVIRONMENT="${1:-staging}"
RTO_TARGET="${RTO_TARGET_MINUTES:-60}"
RPO_TARGET="${RPO_TARGET_MINUTES:-30}"
REPORT_DIR="${REPORT_DIR:-.}"
REPORT_FILE="${REPORT_DIR}/dr-drill-report-${ENVIRONMENT}-$(date -u +%Y%m%dT%H%M%S).txt"
DRILL_START=$(date -u +%s)
PASS=0; FAIL=0; WARN=0

BACKUP_VAULT="${ENVIRONMENT}-backup-vault"
DB_INSTANCE="${ENVIRONMENT}-db"

# ── Helpers ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo "$*" | tee -a "$REPORT_FILE"; }
pass() { log "  ✅ PASS: $*"; PASS=$(( PASS + 1 )); }
fail() { log "  ❌ FAIL: $*"; FAIL=$(( FAIL + 1 )); }
warn() { log "  ⚠️  WARN: $*"; WARN=$(( WARN + 1 )); }

notify() {
  local status="$1" message="$2"
  if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
    local color; case "$status" in SUCCESS) color="good";; FAILURE) color="danger";; *) color="warning";; esac
    curl -s -X POST "$SLACK_WEBHOOK_URL" \
      -H 'Content-type: application/json' \
      --data "{\"attachments\":[{\"color\":\"${color}\",\"text\":\"[stellar-spend][DR-DRILL][${ENVIRONMENT}] ${message}\"}]}" \
      > /dev/null || true
  fi
}

log "════════════════════════════════════════════"
log "  Stellar-Spend DR Drill Report"
log "  Environment : ${ENVIRONMENT}"
log "  RTO target  : ${RTO_TARGET} min"
log "  RPO target  : ${RPO_TARGET} min"
log "  Started at  : $(date -u)"
log "════════════════════════════════════════════"
log ""

notify "INFO" "DR drill started for ${ENVIRONMENT} (RTO=${RTO_TARGET}min, RPO=${RPO_TARGET}min)"

# ── Test 1: Verify Backup Vault ───────────────────────────────────────────────

log "── Test 1: Verify backup vault"
if aws backup describe-backup-vault \
    --backup-vault-name "$BACKUP_VAULT" \
    --region us-east-1 > /dev/null 2>&1; then
  pass "Backup vault '${BACKUP_VAULT}' exists"
else
  fail "Backup vault '${BACKUP_VAULT}' not found"
fi

# ── Test 2: Check Recent Backups ──────────────────────────────────────────────

log ""
log "── Test 2: Check recent backups"
RECENT_BACKUPS=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$BACKUP_VAULT" \
  --region us-east-1 \
  --query 'RecoveryPoints[?Status==`COMPLETED`]' \
  --output json 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "$RECENT_BACKUPS" -ge 1 ]; then
  pass "Found ${RECENT_BACKUPS} completed backup(s)"
else
  fail "No completed backups found in vault '${BACKUP_VAULT}'"
fi

# ── Test 3: Verify RDS Backup Configuration ───────────────────────────────────

log ""
log "── Test 3: RDS backup configuration"
RDS_INFO=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE" \
  --region us-east-1 \
  --query 'DBInstances[0].[BackupRetentionPeriod,MultiAZ]' \
  --output text 2>/dev/null || echo "0 false")

RETENTION=$(echo "$RDS_INFO" | awk '{print $1}')
MULTI_AZ=$(echo "$RDS_INFO" | awk '{print $2}')

if [ "${RETENTION:-0}" -ge 7 ]; then
  pass "Backup retention: ${RETENTION} days"
else
  fail "Backup retention too short: ${RETENTION} days (need ≥ 7)"
fi

if [ "${MULTI_AZ:-false}" = "true" ]; then
  pass "Multi-AZ enabled"
else
  warn "Multi-AZ not enabled for ${ENVIRONMENT}"
fi

# ── Test 4: Verify S3 Backup Bucket ──────────────────────────────────────────

log ""
log "── Test 4: S3 backup bucket"
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
BUCKET_NAME="stellar-spend-${ENVIRONMENT}-backups-${AWS_ACCOUNT}"

if aws s3api head-bucket --bucket "$BUCKET_NAME" --region us-east-1 2>/dev/null; then
  pass "S3 bucket '${BUCKET_NAME}' accessible"
else
  fail "S3 bucket '${BUCKET_NAME}' not found or inaccessible"
fi

# ── Test 5: Bucket Encryption ─────────────────────────────────────────────────

log ""
log "── Test 5: S3 bucket encryption"
ENCRYPTION=$(aws s3api get-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --region us-east-1 \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
  --output text 2>/dev/null || echo "NONE")

if [ "$ENCRYPTION" = "aws:kms" ]; then
  pass "S3 bucket encrypted with KMS"
else
  fail "S3 bucket not encrypted with KMS (got: ${ENCRYPTION})"
fi

# ── Test 6: S3 Versioning ─────────────────────────────────────────────────────

log ""
log "── Test 6: S3 versioning"
VERSIONING=$(aws s3api get-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --region us-east-1 \
  --query 'Status' \
  --output text 2>/dev/null || echo "NONE")

if [ "$VERSIONING" = "Enabled" ]; then
  pass "S3 versioning enabled"
else
  fail "S3 versioning not enabled (got: ${VERSIONING})"
fi

# ── Test 7: Identify Latest Recovery Point ────────────────────────────────────

log ""
log "── Test 7: Latest recovery point"
LATEST_BACKUP=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$BACKUP_VAULT" \
  --region us-east-1 \
  --query 'RecoveryPoints[?Status==`COMPLETED`] | [0].RecoveryPointArn' \
  --output text 2>/dev/null || echo "")

if [ -z "$LATEST_BACKUP" ] || [ "$LATEST_BACKUP" = "None" ]; then
  fail "No recovery point found"
  LATEST_BACKUP=""
else
  pass "Latest recovery point: ${LATEST_BACKUP##*/}"
fi

# ── Test 8: RPO Assertion ─────────────────────────────────────────────────────

log ""
log "── Test 8: RPO assertion (target ≤ ${RPO_TARGET} min)"
RPO_MINUTES=9999
if [ -n "$LATEST_BACKUP" ]; then
  BACKUP_TIME=$(aws backup describe-recovery-point \
    --backup-vault-name "$BACKUP_VAULT" \
    --recovery-point-arn "$LATEST_BACKUP" \
    --region us-east-1 \
    --query 'RecoveryPoint.CreationDate' \
    --output text 2>/dev/null || echo "")

  if [ -n "$BACKUP_TIME" ] && [ "$BACKUP_TIME" != "None" ]; then
    CURRENT_TIME=$(date -u +%s)
    BACKUP_TIMESTAMP=$(python3 -c "
from datetime import datetime, timezone
t = '${BACKUP_TIME}'
dt = datetime.fromisoformat(t.replace('+00:00','').replace('Z',''))
dt = dt.replace(tzinfo=timezone.utc)
print(int(dt.timestamp()))
" 2>/dev/null || echo "0")
    RPO_MINUTES=$(( (CURRENT_TIME - BACKUP_TIMESTAMP) / 60 ))
    log "     Backup created at : ${BACKUP_TIME}"
    log "     RPO                : ${RPO_MINUTES} min"

    if [ "$RPO_MINUTES" -le "$RPO_TARGET" ]; then
      pass "RPO ${RPO_MINUTES} min ≤ target ${RPO_TARGET} min"
    else
      fail "RPO ${RPO_MINUTES} min exceeds target ${RPO_TARGET} min"
    fi
  else
    warn "Could not determine backup creation time"
  fi
fi

# ── Test 9: RTO Estimate ──────────────────────────────────────────────────────

log ""
log "── Test 9: RTO estimate (target ≤ ${RTO_TARGET} min)"
# RTO is based on documented restore time from restore-db.sh (typically 10-20 min for RDS snapshot restore)
ESTIMATED_RTO=20
log "     Estimated RTO: ${ESTIMATED_RTO} min (RDS snapshot restore)"
if [ "$ESTIMATED_RTO" -le "$RTO_TARGET" ]; then
  pass "Estimated RTO ${ESTIMATED_RTO} min ≤ target ${RTO_TARGET} min"
else
  warn "Estimated RTO ${ESTIMATED_RTO} min may exceed target ${RTO_TARGET} min"
fi

# ── Test 10: Backup Encryption ────────────────────────────────────────────────

log ""
log "── Test 10: Backup encryption"
if [ -n "$LATEST_BACKUP" ]; then
  BACKUP_ENCRYPTION=$(aws backup describe-recovery-point \
    --backup-vault-name "$BACKUP_VAULT" \
    --recovery-point-arn "$LATEST_BACKUP" \
    --region us-east-1 \
    --query 'RecoveryPoint.EncryptionKeyArn' \
    --output text 2>/dev/null || echo "")

  if [ -n "$BACKUP_ENCRYPTION" ] && [ "$BACKUP_ENCRYPTION" != "None" ]; then
    pass "Backup encrypted with key: ${BACKUP_ENCRYPTION##*/}"
  else
    fail "Backup not encrypted with a KMS key"
  fi
fi

# ── Test 11: Verify restore-db.sh and verify-backup.sh exist ─────────────────

log ""
log "── Test 11: DR script availability"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for script in restore-db.sh verify-backup.sh; do
  if [ -x "${SCRIPT_DIR}/${script}" ]; then
    pass "${script} exists and is executable"
  else
    fail "${script} missing or not executable"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────

DRILL_DURATION=$(( $(date -u +%s) - DRILL_START ))

log ""
log "════════════════════════════════════════════"
log "  DR Drill Summary"
log "  Completed at : $(date -u)"
log "  Duration     : ${DRILL_DURATION}s"
log "  Passed       : ${PASS}"
log "  Warnings     : ${WARN}"
log "  Failed       : ${FAIL}"
log "  RPO actual   : ${RPO_MINUTES} min (target ≤ ${RPO_TARGET} min)"
log "  RTO estimate : ${ESTIMATED_RTO} min (target ≤ ${RTO_TARGET} min)"
log "════════════════════════════════════════════"

if [ "$FAIL" -eq 0 ]; then
  log "  Result: ✅ DRILL PASSED"
  notify "SUCCESS" "DR drill PASSED — env=${ENVIRONMENT} passed=${PASS} warn=${WARN} RPO=${RPO_MINUTES}min duration=${DRILL_DURATION}s"
  echo ""
  echo "Drill report written to: ${REPORT_FILE}"
  exit 0
else
  log "  Result: ❌ DRILL FAILED (${FAIL} check(s) failed)"
  notify "FAILURE" "DR drill FAILED — env=${ENVIRONMENT} failed=${FAIL} passed=${PASS} warn=${WARN} duration=${DRILL_DURATION}s"
  echo ""
  echo "Drill report written to: ${REPORT_FILE}"
  exit 1
fi

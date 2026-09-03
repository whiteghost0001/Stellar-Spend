#!/usr/bin/env bash
# scripts/rollback-drill.sh
# Periodic rollback drill: deploys a canary image then immediately rolls back,
# asserting that rollback completes within the RTO target.
#
# Usage:
#   ./scripts/rollback-drill.sh [IMAGE_TAG]
#
# Optional environment variables:
#   SLACK_WEBHOOK_URL      - Slack webhook for drill notifications
#   RTO_TARGET_SECONDS     - Maximum acceptable rollback time (default: 120)

set -euo pipefail

IMAGE_TAG="${1:-latest}"
RTO_TARGET="${RTO_TARGET_SECONDS:-120}"
DRILL_START=$(date -u +%s)
DRILL_REPORT="drill-report-$(date -u +%Y%m%dT%H%M%S).txt"

notify() {
  local status="$1" message="$2"
  echo "[DRILL][${status}] ${message}"
  if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
    local color; case "$status" in SUCCESS) color="good";; FAILURE) color="danger";; *) color="warning";; esac
    curl -s -X POST "$SLACK_WEBHOOK_URL" \
      -H 'Content-type: application/json' \
      --data "{\"attachments\":[{\"color\":\"${color}\",\"text\":\"[stellar-spend][DRILL] ${message}\"}]}" \
      > /dev/null || true
  fi
}

echo "==> Starting rollback drill at $(date -u)" | tee "$DRILL_REPORT"
echo "    Image tag : ${IMAGE_TAG}" | tee -a "$DRILL_REPORT"
echo "    RTO target: ${RTO_TARGET}s" | tee -a "$DRILL_REPORT"
echo "" | tee -a "$DRILL_REPORT"

notify "INFO" "Rollback drill started — image=${IMAGE_TAG}"

# Step 1: deploy new image
echo "--- Step 1: Deploying ${IMAGE_TAG} (drill target)..." | tee -a "$DRILL_REPORT"
if ! ./scripts/blue-green-deploy.sh "${IMAGE_TAG}" >> "$DRILL_REPORT" 2>&1; then
  echo "ERROR: Deploy step failed. Drill aborted." | tee -a "$DRILL_REPORT"
  notify "FAILURE" "Drill ABORTED — deploy step failed"
  exit 1
fi
echo "    Deploy complete." | tee -a "$DRILL_REPORT"

# Step 2: trigger rollback and measure time
echo "--- Step 2: Triggering rollback..." | tee -a "$DRILL_REPORT"
ROLLBACK_START=$(date -u +%s)
if ! ./scripts/rollback.sh >> "$DRILL_REPORT" 2>&1; then
  echo "ERROR: Rollback step failed." | tee -a "$DRILL_REPORT"
  notify "FAILURE" "Drill FAILED — rollback step failed"
  exit 1
fi
ROLLBACK_DURATION=$(( $(date -u +%s) - ROLLBACK_START ))

# Step 3: assert RTO
echo "--- Step 3: Asserting RTO..." | tee -a "$DRILL_REPORT"
echo "    Rollback duration : ${ROLLBACK_DURATION}s" | tee -a "$DRILL_REPORT"
echo "    RTO target        : ${RTO_TARGET}s" | tee -a "$DRILL_REPORT"

TOTAL_DURATION=$(( $(date -u +%s) - DRILL_START ))

if [ "$ROLLBACK_DURATION" -le "$RTO_TARGET" ]; then
  echo "    RTO assertion     : PASSED" | tee -a "$DRILL_REPORT"
  echo "" | tee -a "$DRILL_REPORT"
  echo "==> Rollback drill PASSED. Total duration: ${TOTAL_DURATION}s" | tee -a "$DRILL_REPORT"
  notify "SUCCESS" "Rollback drill PASSED — rollback=${ROLLBACK_DURATION}s RTO=${RTO_TARGET}s total=${TOTAL_DURATION}s"
else
  echo "    RTO assertion     : FAILED (${ROLLBACK_DURATION}s > ${RTO_TARGET}s)" | tee -a "$DRILL_REPORT"
  echo "" | tee -a "$DRILL_REPORT"
  echo "==> Rollback drill FAILED (RTO exceeded). Total duration: ${TOTAL_DURATION}s" | tee -a "$DRILL_REPORT"
  notify "FAILURE" "Rollback drill FAILED — rollback=${ROLLBACK_DURATION}s exceeded RTO=${RTO_TARGET}s"
  exit 1
fi

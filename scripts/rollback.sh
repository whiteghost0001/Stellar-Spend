#!/usr/bin/env bash
# rollback.sh
# Rolls back to the previously active blue-green environment.
#
# Usage:
#   ./scripts/rollback.sh
#
# Optional environment variables:
#   SLACK_WEBHOOK_URL   - Slack webhook for rollback notifications
#   DEPLOY_HISTORY_FILE - Path to deploy history log (default: .deploy-history)

set -euo pipefail

HEALTH_URL="http://localhost"
HEALTH_RETRIES=6
HEALTH_INTERVAL=5
DEPLOY_HISTORY_FILE="${DEPLOY_HISTORY_FILE:-.deploy-history}"
ROLLBACK_START=$(date -u +%s)

# ── Notification helper ───────────────────────────────────────────────────────

notify() {
  local status="$1" message="$2"
  echo "==> [NOTIFY] ${status}: ${message}"
  if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
    local color
    case "$status" in
      SUCCESS) color="good" ;;
      FAILURE) color="danger" ;;
      *)       color="warning" ;;
    esac
    curl -s -X POST "$SLACK_WEBHOOK_URL" \
      -H 'Content-type: application/json' \
      --data "{\"attachments\":[{\"color\":\"${color}\",\"text\":\"[stellar-spend] ${message}\"}]}" \
      > /dev/null || true
  fi
}

# ── Deploy history ────────────────────────────────────────────────────────────

record_rollback() {
  local status="$1" active="$2" duration="$3"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) image=rollback slot=${active} status=${status} duration=${duration}s" \
    >> "$DEPLOY_HISTORY_FILE"
}

if [ ! -f .active-env ]; then
  echo "ERROR: .active-env not found. Cannot determine current environment." >&2
  exit 1
fi

CURRENT=$(cat .active-env)
if [ "$CURRENT" = "blue" ]; then
  PREV="green"; PREV_PORT=3001; CURRENT_PORT=3000
else
  PREV="blue";  PREV_PORT=3000; CURRENT_PORT=3001
fi

echo "==> Rolling back from ${CURRENT} to ${PREV}..."
notify "INFO" "Rollback started — reverting from ${CURRENT} to ${PREV}"

# Start the previous environment if not already running
docker compose -f "docker-compose.${PREV}.yml" up -d

# Health-check the previous environment
for i in $(seq 1 "$HEALTH_RETRIES"); do
  if curl -sf "${HEALTH_URL}:${PREV_PORT}/api/health" | grep -q '"status":"ok"'; then
    echo "  Previous environment ${PREV} is healthy"
    break
  fi
  if [ "$i" -eq "$HEALTH_RETRIES" ]; then
    DURATION=$(( $(date -u +%s) - ROLLBACK_START ))
    record_rollback "FAILED" "$CURRENT" "$DURATION"
    notify "FAILURE" "Rollback FAILED — ${PREV} not healthy. Manual intervention required."
    echo "ERROR: Previous environment ${PREV} is not healthy. Manual intervention required." >&2
    exit 1
  fi
  echo "  Waiting for ${PREV}... (${i}/${HEALTH_RETRIES})"
  sleep "$HEALTH_INTERVAL"
done

# Switch traffic back
echo "$PREV" > .active-env
echo "==> Traffic switched back to ${PREV} (port ${PREV_PORT})"

# Stop the bad environment
docker compose -f "docker-compose.${CURRENT}.yml" down

DURATION=$(( $(date -u +%s) - ROLLBACK_START ))
record_rollback "SUCCESS" "$PREV" "$DURATION"
notify "SUCCESS" "Rollback SUCCESS — active=${PREV} duration=${DURATION}s"
echo "==> Rollback complete. Active: ${PREV} (${DURATION}s)"

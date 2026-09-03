#!/bin/bash
set -euo pipefail

LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../logs/rotations"
AUDIT_LOG="$LOG_DIR/audit.log"

echo "📋 Audit Log Viewer"
echo "==================="

if [[ -f "$AUDIT_LOG" ]]; then
    tail -n 20 "$AUDIT_LOG"
else
    echo "No audit log found yet. Run a rotation first."
fi

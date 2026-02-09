#!/bin/bash
# =============================================================================
# OpenClaw Secrets Audit — All Instances
#
# Runs the secrets audit against all OpenClaw instances via SSH.
# Run this from your local machine (not on the instances themselves).
#
# Usage: bash audit-all.sh [host1:instance1] [host2:instance2] ...
#
# Examples:
#   bash audit-all.sh jake:jake clay:clay reed:reed
#   bash audit-all.sh myserver:mybot
#
# If no arguments given, reads from ~/.openclaw-instances (one per line):
#   jake:jake
#   clay:clay
#   reed:reed
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT_SCRIPT="${SCRIPT_DIR}/audit-secrets.sh"
INSTANCES_FILE="${HOME}/.openclaw-instances"

# Build instance list from args or config file
INSTANCES=()
if [ $# -gt 0 ]; then
  INSTANCES=("$@")
elif [ -f "$INSTANCES_FILE" ]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    INSTANCES+=("$line")
  done < "$INSTANCES_FILE"
else
  echo "Usage: audit-all.sh [host:instance] [host:instance] ..."
  echo ""
  echo "Or create ~/.openclaw-instances with one host:instance per line:"
  echo "  jake:jake"
  echo "  clay:clay"
  echo "  reed:reed"
  exit 1
fi

TOTAL=0
PASSED=0
FAILED=0

echo "=== OpenClaw Secrets Audit — All Instances ==="
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Instances: ${#INSTANCES[@]}"
echo ""

for entry in "${INSTANCES[@]}"; do
  HOST="${entry%%:*}"
  INSTANCE="${entry##*:}"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ${HOST} (instance: ${INSTANCE})"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  TOTAL=$((TOTAL + 1))

  if ssh "$HOST" "bash -s" < "$AUDIT_SCRIPT" "$INSTANCE" 2>&1; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
  fi

  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SUMMARY: ${PASSED}/${TOTAL} passed, ${FAILED} failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAILED"

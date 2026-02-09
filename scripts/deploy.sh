#!/bin/bash
# =============================================================================
# OpenClaw Deploy Script
#
# Deploys or updates an OpenClaw instance on the current host.
#
# Usage: bash deploy.sh <instance-name> [aws-region]
#
# Example: bash deploy.sh mybot us-east-2
# =============================================================================
set -euo pipefail

INSTANCE_NAME="${1:?Usage: deploy.sh <instance-name> [aws-region]}"
AWS_REGION="${2:-us-east-2}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying OpenClaw: ${INSTANCE_NAME} ==="

# Create data directories
echo "Creating data directories..."
mkdir -p "${PROJECT_DIR}/data/${INSTANCE_NAME}/clawd"
mkdir -p "${PROJECT_DIR}/data/${INSTANCE_NAME}/clawd/skills"
mkdir -p "${PROJECT_DIR}/data/${INSTANCE_NAME}/transforms"
mkdir -p "${PROJECT_DIR}/data/${INSTANCE_NAME}/tailscale"
mkdir -p "${PROJECT_DIR}/data/${INSTANCE_NAME}/openclaw-data/agents"
mkdir -p "${PROJECT_DIR}/data/${INSTANCE_NAME}/openclaw-data/telegram"
mkdir -p "${PROJECT_DIR}/data/${INSTANCE_NAME}/openclaw-data/devices"
mkdir -p "${PROJECT_DIR}/data/${INSTANCE_NAME}/openclaw-data/identity"
mkdir -p "${PROJECT_DIR}/data/${INSTANCE_NAME}/openclaw-data/settings"
mkdir -p "${PROJECT_DIR}/data/${INSTANCE_NAME}/openclaw-data/cron"
mkdir -p "${PROJECT_DIR}/data/${INSTANCE_NAME}/openclaw-data/media"

# Build and start
echo "Building and starting container..."
cd "$PROJECT_DIR"
INSTANCE_NAME="$INSTANCE_NAME" AWS_REGION="$AWS_REGION" \
  docker compose up -d --build

# Wait for container to be healthy before auditing
echo "Waiting for container to start..."
sleep 5

# Run secrets audit
echo ""
echo "=== Running secrets audit ==="
bash "${SCRIPT_DIR}/audit-secrets.sh" "$INSTANCE_NAME" || true

echo ""
echo "=== Deploy complete ==="
echo "Container: openclaw-${INSTANCE_NAME}"
echo ""
echo "Useful commands:"
echo "  docker logs -f openclaw-${INSTANCE_NAME}     # Follow logs"
echo "  docker exec -it openclaw-${INSTANCE_NAME} bash  # Shell into container"
echo "  docker compose down                           # Stop"
echo "  docker compose up -d --build                  # Rebuild and restart"
echo "  bash scripts/audit-secrets.sh ${INSTANCE_NAME}  # Re-run secrets audit"

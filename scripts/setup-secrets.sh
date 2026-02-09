#!/bin/bash
# =============================================================================
# OpenClaw AWS Secrets Manager Setup
#
# Creates the expected secret structure in AWS Secrets Manager for a new
# OpenClaw instance. Run this once per instance from a machine with AWS CLI
# configured.
#
# Usage: bash setup-secrets.sh <instance-name> <aws-region>
#
# Example: bash setup-secrets.sh mybot us-east-2
# =============================================================================
set -euo pipefail

INSTANCE_NAME="${1:?Usage: setup-secrets.sh <instance-name> <aws-region>}"
AWS_REGION="${2:-us-east-2}"

echo "=== OpenClaw Secrets Setup ==="
echo "Instance: ${INSTANCE_NAME}"
echo "Region:   ${AWS_REGION}"
echo ""

create_secret() {
  local secret_id="$1"
  local description="$2"
  local template="$3"

  if aws secretsmanager describe-secret --secret-id "$secret_id" --region "$AWS_REGION" &>/dev/null; then
    echo "  EXISTS: ${secret_id}"
  else
    aws secretsmanager create-secret \
      --name "$secret_id" \
      --description "$description" \
      --secret-string "$template" \
      --region "$AWS_REGION" \
      --output text --query 'ARN'
    echo "  CREATED: ${secret_id} (update the placeholder values!)"
  fi
}

echo "Creating per-instance secrets..."
create_secret "openclaw/${INSTANCE_NAME}/anthropic-api" \
  "Anthropic API key for ${INSTANCE_NAME}" \
  '{"api_key":"sk-ant-REPLACE_ME"}'

create_secret "openclaw/${INSTANCE_NAME}/telegram-bot" \
  "Telegram bot token for ${INSTANCE_NAME}" \
  '{"token":"REPLACE_ME"}'

create_secret "openclaw/${INSTANCE_NAME}/gateway-auth" \
  "Gateway auth token and port for ${INSTANCE_NAME}" \
  '{"token":"REPLACE_ME","port":"18789"}'

echo ""
echo "Creating shared secrets (skipped if they already exist)..."
create_secret "openclaw/shared/brave-search-api" \
  "Brave Search API key (shared)" \
  '{"api_key":"REPLACE_ME"}'

create_secret "openclaw/shared/elevenlabs-api" \
  "ElevenLabs API key (shared)" \
  '{"api_key":"REPLACE_ME"}'

create_secret "openclaw/shared/gemini-api" \
  "Gemini API key (shared)" \
  '{"api_key":"REPLACE_ME"}'

create_secret "openclaw/shared/tailscale-authkey" \
  "Tailscale auth key (shared)" \
  '{"authkey":"tskey-auth-REPLACE_ME"}'

echo ""
echo "=== Done ==="
echo ""
echo "IMPORTANT: Update any secrets showing 'REPLACE_ME' with real values:"
echo "  aws secretsmanager put-secret-value \\"
echo "    --secret-id 'openclaw/${INSTANCE_NAME}/anthropic-api' \\"
echo "    --secret-string '{\"api_key\":\"sk-ant-xxxxx\"}' \\"
echo "    --region ${AWS_REGION}"
